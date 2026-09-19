import HealthKit
import SwiftUI
import WatchKit

/// The watch app: one screen, one session, no storage of its own.
///
/// Everything it shows comes from the phone and everything it measures goes
/// back to it, so there is nothing here to restore on launch.
@main
struct VelorkiWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchDelegate.self) private var delegate
    @StateObject private var ride = RideSession.shared

    var body: some Scene {
        WindowGroup {
            RideView(ride: ride)
        }
    }
}

/// Where watchOS hands over a workout the phone asked for.
///
/// A ride started on the phone launches this app through HealthKit's
/// `startWatchApp` (see the phone's AppDelegate); the configuration arrives
/// here, and the session starts without anyone touching the watch.
final class WatchDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        RideSession.shared.startMeasuring()
    }
}
