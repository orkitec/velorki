import SwiftUI

/// SHOT_STILL=1 holds the heart still (RideView's pulse is patched to read
/// this), so a store shot never catches it mid-fade.
let shotStill = ProcessInfo.processInfo.environment["SHOT_STILL"] == "1"

/// The store screenshot's stand-in for RideSession: the members RideView
/// reads, filled from the environment tool/store_watch.sh sets from the
/// figures the phone showed at the same moment of the same ride.
final class RideSession: NSObject, ObservableObject {
    @Published var status = "active"
    @Published var distance = ""
    @Published var elapsed = ""
    @Published var speed = ""
    @Published var turnIcon = ""
    @Published var turnLabel = ""
    @Published var turnDistance = ""
    @Published var offRoute = false
    @Published var accent = ""
    @Published var heartRate: Int?
    @Published var measuring = false
    @Published var problem: String?
    var paused: Bool { status == "paused" }
    var riding: Bool { status == "active" || status == "paused" }
    func start() {}
    func pause() {}
    func resume() {}
    func stop() {}
    func stopHeartRate() {}
    func startHeartRate() {}

    override init() {
        super.init()
        let e = ProcessInfo.processInfo.environment
        status = (e["SHOT_STATUS"] ?? "").isEmpty ? "active" : e["SHOT_STATUS"]!
        distance = e["SHOT_DISTANCE"] ?? ""
        elapsed = e["SHOT_ELAPSED"] ?? ""
        speed = e["SHOT_SPEED"] ?? ""
        turnIcon = e["SHOT_TURN_ICON"] ?? ""
        turnLabel = e["SHOT_TURN_LABEL"] ?? ""
        turnDistance = e["SHOT_TURN_DISTANCE"] ?? ""
        heartRate = Int(e["SHOT_HEART_RATE"] ?? "")
        measuring = heartRate != nil && status != "idle"
    }
}

@main
struct ShotApp: App {
    @StateObject private var ride = RideSession()
    var body: some Scene { WindowGroup { RideView(ride: ride) } }
}
