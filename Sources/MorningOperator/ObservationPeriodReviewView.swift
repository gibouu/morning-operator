import MorningCore
import SwiftUI
import MorningApple
import CryptoKit

/// The period stores its date boundary, never a copy of source text or derived labels.
/// Every destination resolves current acquisitions so corrections and deletion take effect.
struct ObservationPeriodReviewLink: View {
    @Bindable var store: MorningStore
    let endingOn: Date
    var onLearn: () -> Void

    var body: some View {
        NavigationLink {
            ObservationPeriodReviewView(store: store, endingOn: endingOn, onLearn: onLearn)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.stack").foregroundStyle(MorningStyle.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("From your observations").font(.raleway(.subheadline, .medium))
                    Text("Sampled screens across days")
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.raleway(.caption2)).foregroundStyle(MorningStyle.muted)
            }
            .padding(20).foregroundStyle(.primary)
            .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain).accessibilityIdentifier("review.recordedPatterns")
    }
}

private struct ObservationPeriodReviewView: View {
    @Bindable var store: MorningStore
    let endingOn: Date
    var onLearn: () -> Void
    @ViewState<String> private var calendarZone = TimeZone.current.identifier
    @ViewState<ObservationContextSelection?> private var selectedContext = nil

    private var report: ObservationReviewPeriod? {
        try? .init(archive: store.observationArchive, endingOn: endingOn,
                   calendarTimeZoneIdentifier: calendarZone)
    }

    var body: some View {
        MorningList {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if let report, let first = report.dayKeys.first, let last = report.dayKeys.last {
                        Text("\(first) – \(last)").font(.raleway(.subheadline).monospacedDigit())
                    }
                    Text("Screens that appeared across your mornings.")
                        .font(.serif(.title2, .medium))
                    Text("These labels describe sampled screens. They don't measure time in apps, reads or scrolls. Missing samples stay unknown.")
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-testing-observation-review") {
                        Label("Synthetic review fixture", systemImage: "testtube.2")
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    }
                    #endif
                }.padding(.vertical, 6)
            }
            if let report {
                if report.partitions.isEmpty {
                    Section {
                        Text("No dated observations in this period.").foregroundStyle(MorningStyle.muted)
                    }
                }
                ForEach(report.partitions) { partition in
                    Section {
                        Text("\(partition.recognizedDayCount) days with labeled samples · \(partition.observedDayCount) days with observations")
                            .font(.raleway(.subheadline))
                            .accessibilityIdentifier("review.recordings.\(partition.id).coverage")
                        Text("\(partition.unclassifiedDayKeys.count) observed days have no labeled samples. \(partition.missingDayKeys.count) days have no observation.")
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        if !partition.daysWithUnknownMoments.isEmpty {
                            Text("\(partition.daysWithUnknownMoments.count) observed days also contain unresolved samples.")
                                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        }
                        if partition.recurrence.isEmpty {
                            Text("No screen labels are available yet.").foregroundStyle(MorningStyle.muted)
                        }
                        ForEach(partition.recurrence) { context in
                            Button {
                                selectedContext = .init(partitionID: partition.id, contextID: context.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(context.context.displayName).font(.raleway(.subheadline, .medium))
                                    if context.citations.contains(where: { $0.provenance == .userReviewed }) {
                                        Text("Your label").font(.raleway(.caption2)).foregroundStyle(MorningStyle.muted)
                                    }
                                    Text("Seen on \(context.seenDayCount) of \(partition.recognizedDayCount) days with labeled samples")
                                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                                }.padding(.vertical, 4)
                            }.accessibilityIdentifier(contextAccessibilityID(partition.id, context.id))
                        }
                        if !partition.conflictingContextKeys.isEmpty {
                            Text("Conflicting labels are excluded from this pattern list. Their original samples remain in each observation.")
                                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        }
                        DisclosureGroup("The seven days") {
                            ForEach(partition.days.reversed()) { day in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(day.dayKey).font(.raleway(.caption, .medium).monospacedDigit())
                                    if day.clips.isEmpty {
                                        Text("No observation").font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                                    }
                                    ForEach(day.clips) { clip in
                                        NavigationLink {
                                            ObservationHistoryDetail(store: store, observationID: clip.id, onLearn: onLearn)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(clip.sourceLabel).font(.raleway(.subheadline))
                                                Text(clip.sampleCount == 0 ? "Notes only" : "\(clip.recognizedMomentCount) labeled moments · \(clip.unknownMomentCount) unresolved")
                                                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                                            }
                                        }.accessibilityIdentifier("review.recordings.clip.\(clip.id.uuidString)")
                                    }
                                }.padding(.vertical, 6)
                            }
                        }
                    } header: {
                        Text("\(originTitle(partition.origin)) · \(partition.timeZoneIdentifier.replacingOccurrences(of: "_", with: " "))")
                    } footer: {
                        Text(partition.origin == .human
                            ? "Dates use the time zone saved with each observation. Separate clips are never joined into one continuous timeline."
                            : "This evidence stays separate from personal mornings. Dates and origins can be reviewed in the source observation.")
                    }
                }
                if !report.undatedAcquisitionIDs.isEmpty {
                    Section {
                        NavigationLink {
                            ObservationHistoryView(store: store, onlyUndated: true, onLearn: onLearn)
                        } label: { Text("\(report.undatedAcquisitionIDs.count) observations still need a date") }
                    } footer: { Text("Undated observations are outside this period until you assign their observed day.") }
                }
            } else {
                Section { Text("This period could not be displayed. Your saved observations have not been changed.") }
            }
        }
        .scrollContentBackground(.hidden).background(MorningPaper(showsSun: false))
        .navigationTitle("Observed mornings")
        .accessibilityIdentifier("review.recordings")
        .navigationDestination(item: $selectedContext) { selected in
            ObservationRecurrenceSources(store: store, endingOn: endingOn, calendarZone: calendarZone,
                partitionID: selected.partitionID, contextID: selected.contextID, onLearn: onLearn)
        }
    }

    private func originTitle(_ origin: ObservationAcquisitionOrigin) -> String {
        switch origin {
        case .human: AppLanguage.localized("My mornings")
        case .synthetic: AppLanguage.localized("Samples & tests")
        case .automated: AppLanguage.localized("Automated activity")
        case .unknown: AppLanguage.localized("Origin unsure")
        }
    }
}

private struct ObservationRecurrenceSources: View {
    @Bindable var store: MorningStore
    let endingOn: Date
    let calendarZone: String
    let partitionID: String
    let contextID: String
    var onLearn: () -> Void
    @ViewState<ObservationSourceSelection?> private var selectedSource = nil

    private var context: ObservationContextRecurrence? {
        let report = try? ObservationReviewPeriod(archive: store.observationArchive, endingOn: endingOn,
                                                  calendarTimeZoneIdentifier: calendarZone)
        return report?.partitions.first { $0.id == partitionID }?.recurrence.first { $0.id == contextID }
    }

    var body: some View {
        MorningList {
            if let context {
                Section {
                    Text(context.context.displayName).font(.serif(.title2, .medium))
                    Text("Seen on \(context.seenDayCount) distinct days. Open a quote to inspect the original sampled screen.")
                        .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                    Text(context.citations.contains(where: { $0.provenance == .userReviewed })
                         ? "You supplied this label. It stays separate from model labels and doesn't establish an action you took."
                         : "A proposed visual label doesn't establish an app's identity or an action you took.")
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                }
                ForEach(context.citations) { citation in
                    if let source = store.observationArchive.entry(id: citation.acquisitionID) {
                        Section {
                            Button {
                                selectedSource = .init(acquisitionID: source.id, sampleID: citation.sampleID)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(citation.quote).font(.raleway(.subheadline)).lineLimit(4)
                                    if citation.provenance == .userReviewed {
                                        Text("Excerpt selected by you").font(.raleway(.caption2)).foregroundStyle(MorningStyle.muted)
                                    }
                                    Text(source.sourceLabel).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                                }
                            }.accessibilityIdentifier("review.recordings.citation.\(citation.id)")
                        } header: { Text("\(citation.dayKey) · \(citation.timeZoneIdentifier)") }
                    }
                }
            } else {
                ContentUnavailableView("Pattern updated", systemImage: "rectangle.stack",
                    description: Text("The sources changed. Return to observed mornings to see the current patterns."))
            }
        }
        .scrollContentBackground(.hidden).background(MorningPaper(showsSun: false))
        .navigationTitle("Source moments")
        .accessibilityIdentifier("review.recordings.sources")
        .navigationDestination(item: $selectedSource) { selected in
            ObservationSampleSourceView(store: store, acquisitionID: selected.acquisitionID, sampleID: selected.sampleID)
        }
    }
}

private func contextAccessibilityID(_ partition: String, _ context: String) -> String {
    let digest = SHA256.hash(data: Data("\(partition)|\(context)".utf8))
    return "review.recordings.context." + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
}

private struct ObservationContextSelection: Hashable {
    let partitionID: String
    let contextID: String
}

private struct ObservationSourceSelection: Hashable {
    let acquisitionID: UUID
    let sampleID: UUID
}
