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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                heart
                if ride.riding { figures }
                if !ride.turnLabel.isEmpty { turn }
                controls
                if ride.measuring {
                    Button("Stop heart rate", action: ride.stopHeartRate)
                        .buttonStyle(.bordered)
                }
                Text("Low Power Mode in the watch's settings makes a long ride last.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Velorki")
    }

    private var heart: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill").foregroundStyle(.red)
            if let bpm = ride.heartRate {
                Text("\(bpm)").font(.system(size: 40, weight: .semibold))
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
