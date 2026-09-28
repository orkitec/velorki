import SwiftUI

/// The ride on the wrist: one page with the figures, the next turn and the
/// buttons that steer the phone, all without scrolling on the smallest watch,
/// and a second page below it for the heart rate switch and the footnotes.
///
/// Its own words come from `Localizable.xcstrings`. Every figure on it — the
/// distance, the clock, the speed, the name of the turn — is formatted and
/// translated by the phone before it is sent, because the phone knows the
/// rider's language and units.
struct RideView: View {
    @ObservedObject var ride: RideSession

    /// The phone's accent, or the app's default lime while the phone has
    /// not said yet. Buttons, the title and the heart take it, so the wrist
    /// matches.
    private var accent: Color { Color(hex: ride.accent) ?? Color(hex: "#C8F542")! }

    /// Text on a filled accent button: black on a light accent such as the
    /// default lime, white on a dark one. The system would use white on both.
    private var onAccent: Color { Color.isLight(hex: ride.accent.isEmpty ? "#C8F542" : ride.accent) ? .black : .white }

    /// The figures' face. Text styles scale with the watch, so one scale
    /// fits the 40 mm case and the Ultra alike.
    private static let figureFont = Font.system(.title3, design: .rounded).weight(.semibold).monospacedDigit()

    var body: some View {
        NavigationStack {
            TabView {
                ridePage.navigationTitle(title)
                morePage.navigationTitle(title)
            }
            .tabViewStyle(.verticalPage)
        }
        .tint(accent)
    }

    /// Beside the clock: what the ride is doing, or the app's name when
    /// there is no ride.
    private var title: Text {
        if !ride.riding { return Text(verbatim: "Velorki") }
        return ride.paused ? Text("Paused") : Text("Riding")
    }

    // MARK: The ride page

    /// Figures at the top, controls at the bottom. The controls never
    /// shrink; the figures and the turn do, so the buttons stay on screen
    /// on the smallest watch and at large text sizes.
    private var ridePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            if ride.riding {
                figures.fixedSize(horizontal: false, vertical: true)
            } else {
                heart(font: .system(.title, design: .rounded).weight(.semibold).monospacedDigit())
                Text("Start a ride here or on the phone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
            }
            Spacer(minLength: 4)
            if let problem = ride.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .lineLimit(4)
                    .minimumScaleFactor(0.6)
            } else if ride.riding && !ride.turnLabel.isEmpty {
                turn
            }
            Spacer(minLength: 4)
            controls
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scenePadding(.horizontal)
        .padding(.bottom, 4)
        // The buttons sit on the bottom edge, as the system's own controls
        // do, rather than a band above it.
        .ignoresSafeArea(edges: .bottom)
    }

    /// Heart rate and speed, distance and time, two by two.
    private var figures: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
            GridRow {
                heart(font: Self.figureFont)
                figure(ride.speed)
            }
            GridRow {
                figure(ride.distance)
                figure(ride.elapsed)
            }
        }
        .foregroundStyle(ride.paused ? .secondary : .primary)
    }

    /// A figure with its unit set small, as the heart rate is, so four fit
    /// side by side at one size.
    private func figure(_ text: String, font: Font = figureFont) -> some View {
        let (value, unit) = Self.split(text)
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value).font(font)
            if let unit {
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "23.8 km/h" as "23.8" and "km/h": the phone's text split at its last
    /// space, when what comes before holds a digit and what follows none.
    /// Anything else, such as "1:12:05", stays whole.
    static func split(_ text: String) -> (String, String?) {
        guard let space = text.lastIndex(where: \.isWhitespace) else { return (text, nil) }
        let value = text[..<space].trimmingCharacters(in: .whitespaces)
        let unit = text[text.index(after: space)...]
        guard value.contains(where: \.isNumber), !unit.isEmpty, !unit.contains(where: \.isNumber)
        else { return (text, nil) }
        return (value, String(unit))
    }

    private func heart(font: Font) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            // Beats while measuring; still when paused or idle.
            Image(systemName: "heart.fill")
                .font(.footnote)
                .foregroundStyle(ride.measuring && !ride.paused ? accent : Color.secondary)
                .symbolEffect(.pulse, options: .repeating, isActive: ride.measuring && !ride.paused)
            if let bpm = ride.heartRate {
                Text(verbatim: "\(bpm)").font(font)
                Text("bpm").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(verbatim: ride.measuring ? "…" : "--")
                    .font(font)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The next turn: how far, then what. Orange while off the route.
    private var turn: some View {
        HStack(spacing: 6) {
            if !ride.turnIcon.isEmpty {
                Image(systemName: ride.turnIcon)
                    .font(.title3.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 0) {
                if !ride.turnDistance.isEmpty {
                    figure(ride.turnDistance, font: .system(.headline, design: .rounded).monospacedDigit())
                }
                Text(ride.turnLabel)
                    .font(.footnote)
                    .lineLimit(2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .foregroundStyle(ride.offRoute ? .orange : .primary)
    }

    @ViewBuilder private var controls: some View {
        if !ride.riding {
            Button("Start ride", action: ride.start)
                .buttonStyle(.borderedProminent)
                .foregroundStyle(onAccent)
        } else {
            HStack(spacing: 6) {
                if ride.paused {
                    Button(action: ride.resume) { fitted("Resume") }
                } else {
                    Button(action: ride.pause) { fitted("Pause") }
                }
                Button(action: ride.stop) { fitted("Finish") }
            }
            .buttonStyle(.bordered)
        }
    }

    /// A button's word, shrunk rather than cut on a narrow watch.
    private func fitted(_ key: LocalizedStringKey) -> some View {
        Text(key).lineLimit(1).minimumScaleFactor(0.6)
    }

    // MARK: The page below

    /// What the rider needs now and then: the heart rate switch, and what
    /// Finish and Low Power Mode do.
    private var morePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if ride.measuring {
                    Button("Stop heart rate", action: ride.stopHeartRate)
                        .buttonStyle(.bordered)
                } else if ride.riding && !ride.paused {
                    Button("Start heart rate", action: ride.startHeartRate)
                        .buttonStyle(.bordered)
                }
                if ride.riding {
                    Text("Finish opens the save sheet on the phone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("Low Power Mode in the watch's settings makes a long ride last.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
