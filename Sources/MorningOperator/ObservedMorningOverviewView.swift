import SwiftUI
import MorningCore
import MorningApple

/// A compact projection of the current archive. Each origin and zone keeps its own
/// denominator; recurring labels never imply a typical sequence or measured use.
struct ObservedMorningOverviewView: View {
    @Bindable var store: MorningStore
    let report: ObservationReviewPeriod
    let endingOn: Date
    var onLearn: () -> Void

    private var partitions: [ObservationReviewPartition] {
        report.partitions.sorted {
            let left = ObservedMorningPresentation.priority($0.origin)
            let right = ObservedMorningPresentation.priority($1.origin)
            return left == right ? $0.id < $1.id : left < right
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your observed mornings")
                    .font(.system(.title2, design: .serif, weight: .medium))
                    .accessibilityIdentifier("review.observedOverview")
            }
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(partitions.prefix(3))) { partition in
                    let clips = partition.days.flatMap(\.clips)
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ObservedMorningPresentation.originTitle(partition.origin, sourceLabels: clips.map(\.sourceLabel)))
                                .font(.subheadline.weight(.semibold))
                                .accessibilityIdentifier("review.observed.group.\(partition.id)")
                            Text(partition.timeZoneIdentifier).font(.caption).foregroundStyle(MorningStyle.muted)
                            Text("\(partition.recognizedDayCount) \(partition.recognizedDayCount == 1 ? "day" : "days") with labeled samples · \(partition.observedDayCount) \(partition.observedDayCount == 1 ? "day" : "days") with observations")
                                .font(.caption).foregroundStyle(MorningStyle.muted)
                                .accessibilityIdentifier("review.observed.coverage.\(partition.id)")
                        }
                        let contexts = partition.recurrence.sorted {
                            $0.seenDayCount == $1.seenDayCount ? $0.id < $1.id : $0.seenDayCount > $1.seenDayCount
                        }
                        if contexts.isEmpty {
                            Text("No screen labels yet. Your saved sources remain available.")
                                .font(.subheadline).foregroundStyle(MorningStyle.muted)
                        }
                        ForEach(Array(contexts.prefix(3))) { context in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(context.context.displayName).font(.subheadline.weight(.medium)).lineLimit(2)
                                    if context.citations.contains(where: { $0.provenance == .userReviewed }) {
                                        Text("Your label").font(.caption2).foregroundStyle(MorningStyle.muted)
                                    }
                                }
                                Spacer(minLength: 6)
                                Text("\(context.seenDayCount) of \(partition.recognizedDayCount) labeled days")
                                    .font(.caption).foregroundStyle(MorningStyle.muted).multilineTextAlignment(.trailing)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("review.observed.context.\(partition.id).\(context.context.key)")
                        }
                        if contexts.count > 3 {
                            Text("Showing 3 of \(contexts.count) labels. All labels and quotations are below.")
                                .font(.caption).foregroundStyle(MorningStyle.muted)
                        }
                        Text("\(partition.unclassifiedDayKeys.count) observed \(partition.unclassifiedDayKeys.count == 1 ? "day" : "days") without labels · \(partition.missingDayKeys.count) dates without observations")
                            .font(.caption).foregroundStyle(MorningStyle.muted)
                        if !partition.daysWithUnknownMoments.isEmpty {
                            Text("Unresolved samples remain on \(partition.daysWithUnknownMoments.count) observed \(partition.daysWithUnknownMoments.count == 1 ? "day" : "days").")
                                .font(.caption).foregroundStyle(MorningStyle.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if partition.id != partitions.prefix(3).last?.id { Divider() }
                }
            }
            .padding(18).background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 22))
            if partitions.count > 3 {
                Text("Showing 3 of \(partitions.count) separate time-zone and origin groups. Open all observations below.")
                    .font(.caption).foregroundStyle(MorningStyle.muted)
            }
            Text("A recorded glimpse, not time spent. These samples don't establish app opens, reads or scrolls.")
                .font(.caption).foregroundStyle(MorningStyle.muted)
            ObservationPeriodReviewLink(store: store, endingOn: endingOn, onLearn: onLearn)
        }
    }
}

/// A day can contain independent recordings from different zones and origins. This
/// view groups their source cards without joining movies or assigning an absent order.
struct ObservedMorningDaySections: View {
    @Bindable var store: MorningStore
    let dayKey: String
    var onLearn: () -> Void

    private var groups: [DayGroup] {
        let entries = store.observationArchive.entries.filter { $0.observedDate?.dayKey == dayKey }
        let grouped = Dictionary(grouping: entries) { "\($0.observedDate!.timeZoneIdentifier)|\($0.origin.rawValue)" }
        return grouped.keys.sorted().compactMap { key in
            guard let values = grouped[key], let first = values.first, let zone = first.observedDate?.timeZoneIdentifier else { return nil }
            return DayGroup(id: key, zone: zone, origin: first.origin, entries: values.sorted {
                ($0.importedAt ?? .distantPast) == ($1.importedAt ?? .distantPast)
                    ? $0.id.uuidString < $1.id.uuidString : ($0.importedAt ?? .distantPast) > ($1.importedAt ?? .distantPast)
            })
        }
    }

    var body: some View {
        ForEach(groups) { group in
            Section {
                ForEach(group.entries) { entry in
                    ObservedMorningClipPreview(store: store, acquisition: entry, onLearn: onLearn)
                }
            } header: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ObservedMorningPresentation.originTitle(group.origin, sourceLabels: group.entries.map(\.sourceLabel)))
                        .accessibilityIdentifier("review.observedDay.group.\(group.id)")
                    Text(group.zone)
                }
            } footer: {
                Text("Each recording is separate. Activity between samples and time spent in apps remain unknown.")
            }
        }
    }

    private struct DayGroup: Identifiable {
        let id: String
        let zone: String
        let origin: ObservationAcquisitionOrigin
        let entries: [ObservationAcquisition]
    }
}

private struct ObservedMorningClipPreview: View {
    @Bindable var store: MorningStore
    let acquisition: ObservationAcquisition
    var onLearn: () -> Void
    @ViewState<Bool> private var showingSamples = false

    private var clip: ObservationClipReview? { try? ObservationClipReview(acquisition: acquisition) }
    private var prefix: String { "review.observedClip" }

    var body: some View {
        // Group exposes sibling native List rows. A NavigationLink inside one
        // enclosing row also activates when its sibling disclosure is tapped.
        Group {
            NavigationLink {
                ObservationHistoryDetail(store: store, observationID: acquisition.id, onLearn: onLearn)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(acquisition.sourceLabel).font(.subheadline.weight(.medium)).lineLimit(2)
                    Text("Open full observation").font(.caption).foregroundStyle(MorningStyle.muted)
                }
            }
            .accessibilityIdentifier("observation.row.\(acquisition.id.uuidString)")
            if let clip, !clip.rows.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    if clip.timelineOrderIsValid {
                        Text(clip.rows.prefix(6).map(ObservedMorningPresentation.momentLabel).joined(separator: " → "))
                            .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("\(prefix).sequence.\(acquisition.id.uuidString)")
                    } else {
                        Text("Chronology unresolved. Original samples stay in extraction order.")
                            .font(.subheadline).foregroundStyle(MorningStyle.muted)
                            .accessibilityIdentifier("\(prefix).sequence.\(acquisition.id.uuidString)")
                    }
                    Text("\(clip.recognizedMomentCount) labeled moments · \(clip.unknownMomentCount) unresolved")
                        .font(.caption).foregroundStyle(MorningStyle.muted)
                    if clip.rows.count > 6 {
                        Text("First 6 of \(clip.rows.count) sampled moments. Open the full observation for every sample.")
                            .font(.caption).foregroundStyle(MorningStyle.muted)
                    }
                    if clip.hasCorrection {
                        Text("Notes were corrected; earlier screen labels were cleared.")
                            .font(.caption).foregroundStyle(MorningStyle.muted)
                    }
                }
                DisclosureGroup(isExpanded: $showingSamples) {
                    ForEach(Array(clip.rows.prefix(6))) { moment in
                        NavigationLink {
                            ObservationSampleSourceView(store: store, acquisitionID: acquisition.id, sampleID: moment.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ObservedMorningPresentation.momentLabel(moment))
                                    .font(.subheadline).lineLimit(2)
                                Text(ObservedMorningPresentation.momentCaption(moment))
                                    .font(.caption).foregroundStyle(MorningStyle.muted)
                            }.padding(.vertical, 4).frame(minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("\(prefix).sample.\(acquisition.id.uuidString).\(moment.id.uuidString)")
                    }
                } label: {
                    Text(clip.rows.count > 6 ? "Inspect these 6 moments" : "Inspect sampled moments")
                        .font(.subheadline)
                        .accessibilityIdentifier("\(prefix).samples.\(acquisition.id.uuidString)")
                }
                .tint(MorningStyle.accent)
            } else {
                Text(acquisition.videoEvidence == nil ? "Written observation · no sampled screens" : "Sample interpretation unavailable. Open the original evidence.")
                    .font(.subheadline).foregroundStyle(MorningStyle.muted)
            }
        }.padding(.vertical, 8)
    }
}

private enum ObservedMorningPresentation {
    static func priority(_ origin: ObservationAcquisitionOrigin) -> Int {
        switch origin { case .human: 0; case .unknown: 1; case .synthetic: 2; case .automated: 3 }
    }
    static func originTitle(_ origin: ObservationAcquisitionOrigin, sourceLabels: [String]) -> String {
        #if DEBUG
        if origin == .human, sourceLabels.contains(where: { $0.hasPrefix("Synthetic fixture · personal branch") }) {
            return sourceLabels.allSatisfy { $0.hasPrefix("Synthetic fixture · personal branch") }
                ? "Synthetic fixture · personal branch" : "My mornings · includes synthetic fixture"
        }
        #endif
        switch origin {
        case .human: return "My mornings"
        case .synthetic: return "Samples & tests"
        case .automated: return "Automated activity"
        case .unknown: return "Origin unsure"
        }
    }
    static func momentLabel(_ moment: ObservationReviewMoment) -> String {
        switch moment.resolution {
        case .recognized: moment.resolvedContext?.displayName ?? "Unknown screen"
        case .ambiguous: "Ambiguous screen"
        case .conflicting: "Unresolved at this timestamp"
        case .unknown: "Unknown screen"
        }
    }
    static func momentCaption(_ moment: ObservationReviewMoment) -> String {
        let seconds = max(0, Int(moment.timeSeconds.rounded()))
        let time = String(format: "%02d:%02d in this recording", seconds / 60, seconds % 60)
        if moment.samples.count > 1 { return "\(time) · \(moment.samples.count) samples share this time" }
        if moment.hasRequestedTimeFallback { return "\(time) · requested time only" }
        if moment.samples.contains(where: { $0.provenance == .userReviewed }) { return "\(time) · Your label" }
        return time
    }
}
