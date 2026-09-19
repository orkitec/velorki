import SwiftUI

/// The watch app: one screen, one session, no storage of its own.
///
/// Everything it shows comes from the phone and everything it measures goes
/// back to it, so there is nothing here to restore on launch.
@main
struct VelorkiWatchApp: App {
    @StateObject private var ride = RideSession()

    var body: some Scene {
        WindowGroup {
            RideView(ride: ride)
        }
    }
}
