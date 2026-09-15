import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
  import ActivityKit

  /// The ride on the lock screen and in the Dynamic Island.
  @available(iOS 16.2, *)
  struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
      ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
        RideLockScreenView(ride: RideState(context.attributes))
          .padding(16)
          .activityBackgroundTint(Color.black.opacity(0.6))
          .activitySystemActionForegroundColor(.white)
      } dynamicIsland: { context in
        let ride = RideState(context.attributes)
        return DynamicIsland {
          DynamicIslandExpandedRegion(.leading) {
            VStack(alignment: .leading, spacing: 2) {
              Text(ride.distance)
                .font(.title2.weight(.semibold))
              Text(ride.elapsed)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          DynamicIslandExpandedRegion(.trailing) {
            Text(ride.speed)
              .font(.title3.weight(.medium))
          }
          DynamicIslandExpandedRegion(.bottom) {
            if ride.hasTurn {
              RideTurnRow(ride: ride)
            }
          }
        } compactLeading: {
          Image(systemName: ride.hasTurn ? ride.turnIcon : "bicycle")
        } compactTrailing: {
          Text(ride.hasTurn ? ride.turnDistance : ride.distance)
            .monospacedDigit()
        } minimal: {
          Image(systemName: ride.hasTurn ? ride.turnIcon : "bicycle")
        }
      }
    }
  }

  /// The card on the lock screen: the distance large, the time and the speed
  /// under it, the next turn at the bottom when there is one.
  @available(iOS 16.2, *)
  struct RideLockScreenView: View {
    let ride: RideState

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          Text(ride.distance)
            .font(.system(size: 40, weight: .semibold, design: .rounded))
            .monospacedDigit()
          Spacer()
          if ride.isPaused {
            Image(systemName: "pause.circle.fill")
              .font(.title2)
              .foregroundStyle(.secondary)
          }
        }
        HStack(spacing: 20) {
          Label(ride.elapsed, systemImage: "clock")
          Label(ride.speed, systemImage: "speedometer")
        }
        .font(.subheadline)
        .monospacedDigit()
        .foregroundStyle(.secondary)

        if ride.hasTurn {
          RideTurnRow(ride: ride)
        }
      }
    }
  }

  /// The turn row: the arrow, what to do, and how far it is.
  @available(iOS 16.2, *)
  struct RideTurnRow: View {
    let ride: RideState

    var body: some View {
      HStack(spacing: 12) {
        Image(systemName: ride.turnIcon)
          .font(.title2)
        VStack(alignment: .leading, spacing: 1) {
          Text(ride.turnLabel)
            .font(.headline)
            .lineLimit(1)
          if !ride.turnDistance.isEmpty {
            Text(ride.turnDistance)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
      }
    }
  }
#endif
