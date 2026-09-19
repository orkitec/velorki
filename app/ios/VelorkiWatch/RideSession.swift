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

    // What the watch measures.
    @Published var heartRate: Int?
    @Published var measuring = false

    /// Whether the phone is running a ride, paused or not.
    var riding: Bool { status == "active" || status == "paused" }

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// The cue the last haptic was played for, so each one is felt once.
    private var lastCue: Double = 0

    /// When the last reading went to the phone: one a second is what the phone
    /// needs, and the builder reports more often than that.
    private var lastSent = Date.distantPast

    /// The one session the app has; the app and its delegate share it.
    static let shared = RideSession()

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - the buttons

    /// Starts a ride: the phone records it, the watch measures it.
    func start() {
        send(["type": "command", "command": "start"])
        startWorkout()
    }

    /// Suspends the ride on the phone. The watch keeps measuring, because a
    /// rider waiting at a light still has a heart rate.
    func pause() { send(["type": "command", "command": "pause"]) }

    /// Continues the ride on the phone.
    func resume() { send(["type": "command", "command": "resume"]) }

    /// Ends the ride. The phone cannot save it without the rider — it is named
    /// on a sheet there — so it stops recording and waits.
    func stop() {
        send(["type": "command", "command": "stop"])
        endWorkout()
    }

    /// Stops measuring without ending the ride: the one thing on this watch
    /// that saves its battery.
    func stopHeartRate() {
        endWorkout()
        send(["type": "heartRateStopped"])
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
        store.requestAuthorization(
            toShare: [HKQuantityType.workoutType()],
            read: [heartRate]
        ) { [weak self] granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { self?.beginSession() }
        }
    }

    private func beginSession() {
        guard session == nil else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .outdoor
        guard
            let session = try? HKWorkoutSession(
                healthStore: store,
                configuration: configuration
            )
        else { return }
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
        builder.beginCollection(withStart: start) { _, _ in }
        measuring = true
    }

    /// Ends the session and throws the workout away.
    ///
    /// The phone writes the ride to Health itself, with the distance and the
    /// track it recorded; a second workout from here would be the same ride
    /// twice in the rider's day.
    private func endWorkout() {
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        measuring = false
        heartRate = nil
        session.end()
        builder.endCollection(withEnd: Date()) { _, _ in
            builder.discardWorkout()
        }
    }

    // MARK: - talking to the phone

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
        // The phone may have ended the ride while this app was not reachable
        // for its stop message; the context says so, and the session goes.
        if status == "idle", session != nil { endWorkout() }
        distance = context["distance"] as? String ?? ""
        elapsed = context["elapsed"] as? String ?? ""
        speed = context["speed"] as? String ?? ""
        turnIcon = context["turnIcon"] as? String ?? ""
        turnLabel = context["turnLabel"] as? String ?? ""
        turnDistance = context["turnDistance"] as? String ?? ""
        offRoute = context["offRoute"] as? Bool ?? false
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
            if action == "start" {
                self.startWorkout()
            } else {
                self.endWorkout()
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
        guard toState == .ended || toState == .stopped else { return }
        DispatchQueue.main.async {
            self.measuring = false
            self.heartRate = nil
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.endWorkout() }
    }
}

extension RideSession: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let type = HKQuantityType(.heartRate)
        guard
            collectedTypes.contains(type),
            let statistics = workoutBuilder.statistics(for: type),
            let quantity = statistics.mostRecentQuantity()
        else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let bpm = Int(quantity.doubleValue(for: unit).rounded())
        guard bpm > 0 else { return }

        DispatchQueue.main.async {
            self.heartRate = bpm
            let now = Date()
            guard now.timeIntervalSince(self.lastSent) >= 1 else { return }
            self.lastSent = now
            self.send([
                "type": "heartRate",
                "bpm": bpm,
                "at": Int(now.timeIntervalSince1970 * 1000),
            ])
        }
    }
}
