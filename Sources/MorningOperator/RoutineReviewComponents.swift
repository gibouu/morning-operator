import SwiftUI
import MorningCore

/// Presentation only. These components never create a routine or change approval.
struct RoutineReviewSummary: View {
    let routine: RoutineVersion
    let sessionActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your daily routine").font(.headline).foregroundStyle(MorningStyle.ink)
            Text("\(routine.steps.count) moments · \(routine.totalDurationMinutes) min planned")
                .font(.subheadline).foregroundStyle(MorningStyle.muted)
            Label(routine.isApproved ? "Approved" : "Draft · review before approval",
                  systemImage: routine.isApproved ? "checkmark.circle" : "pencil")
                .font(.caption).foregroundStyle(MorningStyle.muted)
            if sessionActive {
                Text("Finish or end this morning before editing your routine.")
                    .font(.footnote).foregroundStyle(MorningStyle.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
        .accessibilityIdentifier("routine.summary")
    }
}

struct RoutineMomentRow: View {
    let step: RoutineStep

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: MorningStyle.symbol(for: step.kind))
                .font(.body).frame(width: 34, height: 34)
                .background(MorningStyle.selected, in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title).font(.subheadline.weight(.medium))
                Text(step.automation == nil
                     ? "\(step.durationMinutes) min planned · Your own pace"
                     : "\(step.durationMinutes) min planned · Spoken guidance")
                    .font(.caption).foregroundStyle(MorningStyle.muted)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .foregroundStyle(MorningStyle.ink).padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
