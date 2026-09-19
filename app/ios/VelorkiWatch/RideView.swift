import SwiftUI

/// The one screen: the ride's figures, the next turn, and the buttons that
/// steer the phone.
///
/// Its words are English. Every figure on it — the distance, the clock, the
/// speed, the name of the turn — is formatted and translated by the phone
/// before it is sent, because the phone knows the rider's language and units
/// and this app knows neither.
struct RideView: View {
    @ObservedObject var ride: RideSession

    /// The phone's accent, or the app's default lime while the phone has
    /// not said yet. Buttons and the heart take it, so the wrist matches.
    private var accent: Color { Color(hex: ride.accent) ?? Color(hex: "#C8F542")! }

    /// Text on a filled accent button: black on a light accent such as the
    /// default lime, white on a dark one. The system would use white on both.
    private var onAccent: Color { Color.isLight(hex: ride.accent.isEmpty ? "#C8F542" : ride.accent) ? .black : .white }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                heart
                if let problem = ride.problem {
                    Text(problem).font(.footnote).foregroundStyle(.orange)
                }
                if ride.riding { figures }
                if !ride.turnLabel.isEmpty { turn }
                controls
                if ride.measuring {
                    Button("Stop heart rate", action: ride.stopHeartRate)
                        .buttonStyle(.bordered)
                } else if ride.riding && !ride.paused {
                    Button("Start heart rate", action: ride.startHeartRate)
                        .buttonStyle(.bordered)
                }
                Text("Low Power Mode in the watch's settings makes a long ride last.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Velorki")
        .tint(accent)
    }

    private var heart: some View {
        HStack(spacing: 6) {
            // Beats while measuring; still when paused or idle.
            Image(systemName: "heart.fill")
                .foregroundStyle(ride.measuring && !ride.paused ? accent : Color.secondary)
                .symbolEffect(.pulse, options: .repeating, isActive: ride.measuring && !ride.paused)
            if let bpm = ride.heartRate {
                Text("\(bpm)")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(ride.paused ? .secondary : .primary)
                Text("bpm").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(ride.measuring ? "…" : "--")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var figures: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ride.distance).font(.title3)
            HStack(spacing: 8) {
                Text(ride.elapsed)
                Text(ride.speed)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if ride.status == "paused" {
                Text("Paused").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var turn: some View {
        HStack(spacing: 6) {
            if !ride.turnIcon.isEmpty {
                Image(systemName: ride.turnIcon)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(ride.turnLabel).font(.headline)
                if !ride.turnDistance.isEmpty {
                    Text(ride.turnDistance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(ride.offRoute ? .orange : .primary)
    }

    @ViewBuilder private var controls: some View {
        if !ride.riding {
            Button("Start ride", action: ride.start)
                .buttonStyle(.borderedProminent)
                .foregroundStyle(onAccent)
        } else {
            HStack(spacing: 8) {
                if ride.status == "paused" {
                    Button("Resume", action: ride.resume)
                } else {
                    Button("Pause", action: ride.pause)
                }
                Button("Finish", action: ride.stop)
            }
            .buttonStyle(.bordered)
            Text("Finish opens the save sheet on the phone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

extension Color {
    /// Whether `#RRGGBB` is light enough to want black text on it.
    static func isLight(hex: String) -> Bool {
        guard hex.count == 7, let rgb = UInt32(hex.dropFirst(), radix: 16) else { return false }
        let r = Double((rgb >> 16) & 0xFF), g = Double((rgb >> 8) & 0xFF), b = Double(rgb & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.6
    }

    /// `#RRGGBB` as sent by the phone; nil for anything else.
    init?(hex: String) {
        guard hex.count == 7, hex.hasPrefix("#"),
              let rgb = UInt32(hex.dropFirst(), radix: 16)
        else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
