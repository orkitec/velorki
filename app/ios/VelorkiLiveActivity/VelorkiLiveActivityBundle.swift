import SwiftUI
import WidgetKit

/// The extension's entry point. One widget: the ride.
@main
struct VelorkiLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    // Live Activities need iOS 16.1, and the `ActivityContent` this uses
    // needs 16.2. Below that the bundle is simply empty.
    if #available(iOS 16.2, *) {
      RideLiveActivity()
    }
  }
}
