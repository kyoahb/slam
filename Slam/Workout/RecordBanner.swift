import SwiftUI
import SlamCore

/// Records one ticked set just made, shown at the top of the live workout.
struct RecordBanner: Identifiable, Equatable {
    let id = UUID()
    let exercise: Exercise
    let items: [LiveRecord]

    var title: String {
        items.allSatisfy { $0.kind == .setVolume || $0.kind == .sessionVolume } ? "New Volume Record" : "New PR"
    }
}

struct RecordBannerView: View {
    let banner: RecordBanner

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "medal.fill")
                .font(.system(size: 26))
                .foregroundStyle(Theme.medal)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(banner.title).font(.headline)
                    Text(banner.exercise.name).font(.subheadline).foregroundStyle(Theme.grey).lineLimit(1)
                }
                ForEach(Array(banner.items.prefix(3).enumerated()), id: \.offset) { _, r in
                    let (before, after) = values(r)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.kind.title).font(.subheadline.weight(.semibold))
                        HStack(spacing: 6) {
                            if let before {
                                Text(before).foregroundStyle(Theme.grey)
                                Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(Theme.grey)
                            }
                            Text(after).fontWeight(.semibold).foregroundStyle(Theme.medal)
                        }
                        .font(.subheadline)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.medal.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// What it was and what it is now, in the record's own unit.
    private func values(_ r: LiveRecord) -> (String?, String) {
        let ex = banner.exercise
        switch r.kind {
        case .set:
            return (r.beforeSet.map { SetText.describe($0, ex) }, r.afterSet.map { SetText.describe($0, ex) } ?? "")
        case .heaviest, .e1rm:
            return (r.before.map(Self.kg), Self.kg(r.after))
        case .setVolume, .sessionVolume:
            return (r.before.map(Format.volume), Format.volume(r.after))
        case .reps:
            return (r.before.map { "\(Int($0)) reps" }, "\(Int(r.after)) reps")
        case .seconds:
            return (r.before.map { Format.clock(Int($0)) }, Format.clock(Int(r.after)))
        case .meters:
            let km = ex.type == .distanceDuration
            func text(_ m: Double) -> String { km ? Format.km(m) + " km" : Format.kg(m) + " m" }
            return (r.before.map(text), text(r.after))
        }
    }

    private static func kg(_ v: Double) -> String { Format.kg(v.rounded(toPlaces: 1)) + " kg" }
}
