import Foundation
import HealthKit
import WatchConnectivity
import WatchKit

/// The ride as the watch knows it: what the phone last reported, and the heart
/// rate the watch itself is measuring.
///
/// Two halves that barely touch. One is a `WCSession` delegate: the phone's
/// application context is the screen, its messages ask for the workout to
/// start or stop, and the buttons send commands back. The other is an
/// `HKWorkoutSession` with a live builder, which is the only way watchOS keeps
/// the heart rate sensor running with the wrist down — the workout itself is
/// discarded at the end, because the phone is what writes the ride to Health.
///
/// The protocol is spelled out in README.md here and mirrored in
/// `lib/features/sensors/data/watch_protocol.dart`.
final class RideSession: NSObject, ObservableObject {
    // What the phone reports.
    @Published var status = "idle"
    @Published var distance = ""
    @Published var elapsed = ""
    @Published var speed = ""
    @Published var turnIcon = ""
    @Published var turnLabel = ""
    @Published var turnDistance = ""
    @Published var offRoute = false
    /// The phone's accent colour, `#RRGGBB`; empty until the phone has said.
    @Published var accent = ""

    // What the watch measures.
    @Published var heartRate: Int?
    @Published var measuring = false

    /// The ride is paused, and so is the measuring: the session is ended so
    /// the sensor really rests (a paused HKWorkoutSession keeps sampling),
    /// and the last reading stays on screen dimmed until the ride goes on.
    var paused: Bool { status == "paused" }

    /// Why there is no heart rate, when the watch knows: Health access
    /// refused, or a session watchOS would not run. Shown under the heart.
    @Published var problem: String?

    /// Whether the phone is running a ride, paused or not.
    var riding: Bool { status == "active" || status == "paused" }

    /// Set by the "Stop heart rate" button, cleared when the ride ends: a
    /// ride the phone reports as running starts the measuring again on its
    /// own unless the rider stopped it on purpose.
    private var stoppedByRider = false

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// The cue the last haptic was played for, so each one is felt once.
    private var lastCue: Double = 0

    /// When the last reading went to the phone: one a second is what the phone
    /// needs, and the builder reports more often than that.
    private var lastSent = Date.distantPast

    /// Heart rate samples seen in this session, for the log.
    private var samples = 0

    /// A command the phone has not confirmed yet, resent until its context
    /// shows the status asked for. A phone whose app is closed is launched
    /// by the first message but only listens a moment later, and that first
    /// message is lost; the second or third lands.
    private var pending: (command: String, expects: Set<String>, tries: Int)?
    private var retry: Timer?
    private static let retryEvery: TimeInterval = 2
    private static let retries = 8

    /// The one session the app has; the app and its delegate share it.
    static let shared = RideSession()

    /// `NSLog` rather than `Logger`: it lands on stderr, which is what
    /// `xcrun devicectl device process launch --console` shows from the Mac.
    private func note(_ line: String) { NSLog("velorki watch: %@", line) }

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - the buttons

    /// Starts a ride: the phone records it, the watch measures it.
    func start() {
        note("Start tapped")
        command("start", expecting: ["active", "paused"])
        startWorkout()
    }

    /// Suspends the ride on the phone. The watch keeps measuring, because a
    /// rider waiting at a light still has a heart rate.
    func pause() { command("pause", expecting: ["paused"]) }

    /// Continues the ride on the phone.
    func resume() { command("resume", expecting: ["active"]) }

    /// Ends the ride. The phone cannot save it without the rider — it is named
    /// on a sheet there — so it stops recording and waits.
    func stop() {
        note("Finish tapped")
        command("stop", expecting: ["idle"])
        endWorkout("finish tapped")
    }

    /// Stops measuring without ending the ride: the one thing on this watch
    /// that saves its battery.
    func stopHeartRate() {
        stoppedByRider = true
        endWorkout("stop heart rate tapped")
        send(["type": "heartRateStopped"])
    }

    /// Starts measuring again mid-ride, after "Stop heart rate" or after the
    /// app was closed and reopened.
    func startHeartRate() {
        stoppedByRider = false
        startWorkout()
    }

    // MARK: - the workout

    /// Asks the OS on the watch for the heart rate and starts the session.
    ///
    /// This is the only prompt the rider ever sees on the watch, and it comes
    /// after they switched the watch on in the phone's settings and opened
    /// this app, which is what makes it opt-in.
    /// Starts measuring for a ride the phone started: the phone launched this
    /// app through HealthKit with a workout configuration.
    func startMeasuring() { startWorkout() }

    private func startWorkout() {
        guard session == nil, HKHealthStore.isHealthDataAvailable() else { return }
        let heartRate = HKQuantityType(.heartRate)
        note("Workout share status \(store.authorizationStatus(for: .workoutType()).rawValue) (0 undetermined, 1 denied, 2 allowed)")
        store.requestAuthorization(
            toShare: [HKQuantityType.workoutType()],
            read: [heartRate]
        ) { [weak self] granted, error in
            guard let self else { return }
            if let error {
                self.note("Health authorization failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                guard granted else {
                    self.problem = "Health access is needed: allow it on the watch or in the phone's Health app."
                    return
                }
                self.beginSession()
            }
        }
    }

    private func beginSession() {
        guard session == nil else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .outdoor
        let session: HKWorkoutSession
        do {
            session = try HKWorkoutSession(healthStore: store, configuration: configuration)
        } catch {
            note("Workout session could not be made: \(error.localizedDescription)")
            problem = "The watch would not start a workout: \(error.localizedDescription)"
            return
        }
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: store,
            workoutConfiguration: configuration
        )
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder

        let start = Date()
        session.startActivity(with: start)
        builder.beginCollection(withStart: start) { [weak self] began, error in
            self?.note("Collection began: \(began) \(error?.localizedDescription ?? "")")
        }
        samples = 0
        measuring = true
        problem = nil
        note("Workout session started")
    }

    /// Ends the session and throws the workout away.
    ///
    /// The phone writes the ride to Health itself, with the distance and the
    /// track it recorded; a second workout from here would be the same ride
    /// twice in the rider's day.
    private func endWorkout(_ reason: String, keepReading: Bool = false) {
        note("End asked for: \(reason); session \(session == nil ? "none" : "state \(session!.state.rawValue)")")
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        measuring = false
        if !keepReading { heartRate = nil }
        session.end()
        builder.endCollection(withEnd: Date()) { _, _ in
            builder.discardWorkout()
        }
    }

    // MARK: - talking to the phone

    /// Sends a command and keeps sending it until the phone's context shows
    /// one of the statuses it should lead to, or the tries run out.
    private func command(_ command: String, expecting: Set<String>) {
        pending = (command, expecting, 0)
        resend()
    }

    private func resend() {
        retry?.invalidate()
        retry = nil
        guard var pending else { return }
        guard pending.tries < Self.retries else {
            note("Command \(pending.command) never confirmed")
            self.pending = nil
            // iOS does not launch an app the rider force-quit for a watch
            // message, and a phone out of range hears nothing: only the
            // rider can help, so the wrist says so.
            problem = "The phone did not answer. Open Velorki on the phone and try again."
            return
        }
        pending.tries += 1
        self.pending = pending
        send(["type": "command", "command": pending.command])
        retry = Timer.scheduledTimer(withTimeInterval: Self.retryEvery, repeats: false) { [weak self] _ in
            self?.resend()
        }
    }

    /// The phone's status has come in: a command it confirms is done with.
    private func confirm(_ status: String) {
        guard let pending, pending.expects.contains(status) else { return }
        if pending.tries > 1 { note("Command \(pending.command) confirmed on try \(pending.tries)") }
        self.pending = nil
        problem = nil
        retry?.invalidate()
        retry = nil
    }

    private func send(_ message: [String: Any]) {
        guard WCSession.isSupported() else { return }
        WCSession.default.sendMessage(message, replyHandler: nil) { _ in }
    }

    /// Plays one haptic for a cue the phone reports, at most one per cue.
    private func feel(_ cue: Double) {
        guard cue > 0, cue != lastCue else { return }
        lastCue = cue
        WKInterfaceDevice.current().play(offRoute ? .failure : .notification)
    }

    private func apply(_ context: [String: Any]) {
        status = context["status"] as? String ?? "idle"
        note("Context: status \(status), session \(session == nil ? "none" : "up")")
        confirm(status)
        // The phone may have ended the ride while this app was not reachable
        // for its stop message; the context says so, and the session goes.
        if status == "idle" {
            stoppedByRider = false
            if session != nil { endWorkout("phone reports the ride over") }
        }
        // A paused ride — by hand or the phone's auto-pause at a standstill —
        // ends the session, so the sensor rests and a wait at a light is
        // not part of the ride's heart rate; the last reading stays on
        // screen. A ride going on again, or one that is running while this
        // app is not measuring (opened late, or reopened after watchOS
        // closed it), starts measuring by itself, unless the rider stopped
        // it.
        if status == "paused", session != nil {
            endWorkout("ride paused", keepReading: true)
        }
        if status == "active", session == nil, !stoppedByRider { startWorkout() }
        distance = context["distance"] as? String ?? ""
        elapsed = context["elapsed"] as? String ?? ""
        speed = context["speed"] as? String ?? ""
        turnIcon = context["turnIcon"] as? String ?? ""
        turnLabel = context["turnLabel"] as? String ?? ""
        turnDistance = context["turnDistance"] as? String ?? ""
        offRoute = context["offRoute"] as? Bool ?? false
        accent = context["accent"] as? String ?? ""
        // The phone sends milliseconds as an integer; it arrives as an
        // NSNumber either way, and nothing here does arithmetic on it.
        feel((context["cue"] as? NSNumber)?.doubleValue ?? 0)
    }
}

// MARK: - WCSessionDelegate

extension RideSession: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Whatever the phone last said is waiting in the context; a watch app
        // opened mid-ride shows the ride rather than an empty screen.
        let context = session.receivedApplicationContext
        guard !context.isEmpty else { return }
        DispatchQueue.main.async { self.apply(context) }
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        DispatchQueue.main.async { self.apply(applicationContext) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard
            message["type"] as? String == "workout",
            let action = message["action"] as? String
        else { return }
        DispatchQueue.main.async {
            self.note("Phone asks workout \(action)")
            if action == "start" {
                self.startWorkout()
            } else {
                self.endWorkout("phone asked")
            }
        }
    }
}

// MARK: - the live workout

extension RideSession: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        note("Workout session state \(fromState.rawValue) -> \(toState.rawValue)")
        guard toState == .ended || toState == .stopped else { return }
        DispatchQueue.main.async {
            self.measuring = false
            // A session that ended on its own — not for a pause — takes
            // its reading with it.
            if !self.paused { self.heartRate = nil }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        note("Workout session failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.endWorkout("session failed")
            self.problem = "The workout stopped: \(error.localizedDescription)"
        }
    }
}

extension RideSession: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let type = HKQuantityType(.heartRate)
        guard collectedTypes.contains(type) else {
            note("Collected \(collectedTypes.map(\.identifier).joined(separator: ","))")
            return
        }
        guard
            let statistics = workoutBuilder.statistics(for: type),
            let quantity = statistics.mostRecentQuantity()
        else {
            note("Heart rate collected but no statistics yet")
            return
        }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let bpm = Int(quantity.doubleValue(for: unit).rounded())
        samples += 1
        if samples <= 10 || samples % 30 == 0 { note("Heart rate sample \(samples): \(bpm)") }
        guard bpm > 0 else { return }

        DispatchQueue.main.async {
            self.heartRate = bpm
            let now = Date()
            guard now.timeIntervalSince(self.lastSent) >= 1 else { return }
            self.lastSent = now
            // Int64, not Int: on the arm64_32 watches (Series 4 to 8, SE) an
            // Int is 32 bits, and milliseconds since 1970 overflow it — a
            // trap on the first sample, and the app was gone.
            self.send([
                "type": "heartRate",
                "bpm": bpm,
                "at": Int64(now.timeIntervalSince1970 * 1000),
            ])
        }
    }
}
