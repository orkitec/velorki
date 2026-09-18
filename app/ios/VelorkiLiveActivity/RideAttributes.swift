import Foundation

#if canImport(ActivityKit)
  import ActivityKit

  /// The pipe the `live_activities` plugin writes through.
  ///
  /// The name is not ours to choose: the plugin requests the activity with
  /// exactly this attribute type, and an extension that declares a different
  /// one starts an activity that never appears. The real figures do not travel
  /// in `ContentState` either — ActivityKit cannot diff them — but through the
  /// App Group's `UserDefaults`; `updateId` only changes so the system knows
  /// there is something new to draw.
  struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryData = ContentState

    public struct ContentState: Codable, Hashable {
      var appGroupId: String?
      var updateId: Double?
    }

    var id = UUID()
  }

  extension LiveActivitiesAppAttributes {
    /// The key one value of this activity is stored under.
    func prefixedKey(_ key: String) -> String {
      "\(id)_\(key)"
    }
  }

  /// The App Group both targets are members of. The same string stands in
  /// `liveActivityAppGroupId` on the Dart side; change one and change the other.
  let velorkiSharedDefaults = UserDefaults(suiteName: "group.com.orkitec.velorki")

  /// One frame of the ride, read out of the App Group.
  ///
  /// The field names are the keys `rideActivityData` writes in
  /// `lib/features/recording/application/ride_notification_updater.dart`.
  /// Everything is already formatted and translated there, because the app
  /// knows the rider's language and units and this extension does not.
  @available(iOS 16.2, *)
  struct RideState {
    /// How far the ride has come, e.g. "3.2 km".
    let distance: String

    /// How long it has been going, e.g. "00:42".
    let elapsed: String

    /// How fast the rider is going right now, e.g. "18.0 km/h".
    let speed: String

    /// The heart rate as a bare number, e.g. "142"; empty when no sensor is
    /// reporting one.
    let heartRate: String

    /// The SF Symbol of the next turn, empty when nothing is being navigated.
    let turnIcon: String

    /// What to do at that turn, e.g. "Turn left", or "Off route".
    let turnLabel: String

    /// How far it is, e.g. "150 m"; empty when there is nothing to measure to.
    let turnDistance: String

    /// Whether the recording is paused.
    let isPaused: Bool

    init(_ attributes: LiveActivitiesAppAttributes) {
      func text(_ key: String) -> String {
        velorkiSharedDefaults?.string(forKey: attributes.prefixedKey(key)) ?? ""
      }
      distance = text("distance")
      elapsed = text("elapsed")
      speed = text("speed")
      heartRate = text("heartRate")
      turnIcon = text("turnIcon")
      turnLabel = text("turnLabel")
      turnDistance = text("turnDistance")
      isPaused =
        (velorkiSharedDefaults?.integer(forKey: attributes.prefixedKey("paused")) ?? 0) != 0
    }

    /// Whether there is a turn worth showing.
    var hasTurn: Bool {
      !turnLabel.isEmpty && !turnIcon.isEmpty
    }

    /// Whether a sensor is reporting a heart rate.
    var hasHeartRate: Bool {
      !heartRate.isEmpty
    }
  }
#endif
