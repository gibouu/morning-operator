import SwiftUI
import MorningCore
import MorningApple

/// A transient projection of the current acquisition. Selection retains only a source ID;
/// original OCR and quoted interpretation are always resolved again from the parent value.
@MainActor
struct ObservationClipTimelineView: View {
    @Bindable var store: MorningStore
    let acquisition: ObservationAcquisition
    @ViewState<Bool> private var showingSamples = false
    @ViewState<ObservationMomentSelection?> private var selection = nil

    private var review: ObservationClipReview? { try? ObservationClipReview(acquisition: acquisition) }
    private var prefix: String { "observation.timeline.\(acquisition.id.uuidString)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let review, !review.rows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(review.timelineOrderIsValid ? "Sampled moments" : "Saved samples").font(.headline)
                    Text(summary(review))
                        .font(.subheadline).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("\(prefix).summary")
                    if review.timelineOrderIsValid {
                        Text(sequence(review))
                            .font(.subheadline.weight(.medium)).lineLimit(3)
                            .accessibilityIdentifier("\(prefix).sequence")
                        if review.rows.count > 6 {
                            Text("First 6 of \(review.rows.count) sampled moments")
                                .font(.caption).foregroundStyle(MorningStyle.muted)
                        }
                    }
                    if review.timelineOrderIsValid, review.recognizedMomentCount > 0 {
                        Text(returnSummary(review)).font(.caption).foregroundStyle(MorningStyle.muted)
                            .accessibilityIdentifier("\(prefix).returns")
                    }
                    if let message = interpretationMessage(review) {
                        Text(message).font(.caption).foregroundStyle(MorningStyle.muted)
                            .accessibilityIdentifier("\(prefix).status")
                    }
                }

                // Keep the identifier on the disclosure's label, not its container: an
                // inherited container identifier can hide the child source buttons in AX.
                DisclosureGroup(isExpanded: $showingSamples) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(review.timelineOrderIsValid ? "Activity between these sampled moments is unknown." : "Original samples in extraction order")
                            .font(.caption).foregroundStyle(MorningStyle.muted)
                            .padding(.bottom, 4)
                        ForEach(review.rows) { moment in
                            Button { selection = .init(id: moment.id) } label: {
                                momentRow(moment)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("\(observationSampleTime(moment.timeSeconds)), \(momentLabel(moment))")
                            .accessibilityValue(momentCaveat(moment) ?? "Sampled screen")
                            .accessibilityHint("Shows original text and quoted evidence")
                            .accessibilityIdentifier("\(prefix).point.\(moment.id.uuidString)")
                            if moment.id != review.rows.last?.id { Divider().padding(.leading, 64) }
                        }
                    }.padding(.top, 8)
                } label: {
                    Text("View sampled screens")
                        .font(.subheadline.weight(.medium))
                        .accessibilityIdentifier("\(prefix).samples")
                }
                .tint(MorningStyle.accent)

                Text("Labels come from recognition or your review. Samples can miss activity and don't measure time spent, taps, reads or scrolls.")
                    .font(.caption).foregroundStyle(MorningStyle.muted)
            } else {
                Text(acquisition.videoEvidence == nil ? "No sampled recording is attached to this observation." : "The sampled interpretation can't be displayed. Original evidence remains available below.")
                    .font(.subheadline).foregroundStyle(MorningStyle.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .sheet(item: $selection) { selected in
            NavigationStack {
                if let current = review,
                   let moment = current.rows.first(where: { $0.id == selected.id }),
                   let sampleID = moment.samples.first?.id {
                    ObservationSampleSourceView(store: store, acquisitionID: acquisition.id, sampleID: sampleID, managesEntryOccupancy: false)
                } else {
                    ContentUnavailableView("Sample changed", systemImage: "doc.text.magnifyingglass",
                                           description: Text("Return to the observation to review its current evidence."))
                        .navigationTitle("Sampled moment")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { selection = nil }
                                    .accessibilityIdentifier("observation.sample.close")
                            }
                        }
                }
            }
        }
        .onChange(of: acquisition) { _, updated in
            // Keep an open sample on label edits; its ID resolves the current source.
            if let selection, !(updated.videoEvidence?.frames.contains { $0.id == selection.id } ?? false) {
                self.selection = nil
            }
        }
    }

    private func momentRow(_ moment: ObservationReviewMoment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(observationSampleTime(moment.timeSeconds))
                .font(.caption.monospacedDigit()).foregroundStyle(MorningStyle.muted)
                .frame(minWidth: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(momentLabel(moment)).font(.subheadline.weight(.medium)).foregroundStyle(MorningStyle.ink)
                if let caveat = momentCaveat(moment) {
                    Text(caveat).font(.caption).foregroundStyle(MorningStyle.muted)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                .foregroundStyle(MorningStyle.muted).accessibilityHidden(true)
        }
        .padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func summary(_ value: ObservationClipReview) -> String {
        guard value.timelineOrderIsValid else { return "\(value.sampleCount) source samples · chronology unresolved" }
        return "\(value.recognizedMomentCount) of \(value.rows.count) sampled moments labeled · \(value.unknownMomentCount) unresolved"
    }

    private func sequence(_ value: ObservationClipReview) -> String {
        value.rows.prefix(6).map(momentLabel).joined(separator: " → ")
    }

    private func returnSummary(_ value: ObservationClipReview) -> String {
        let count = value.traceReport?.apps.reduce(0) { $0 + $1.minimumVisibleReturnCount } ?? 0
        if count == 0 { return "No return is established by these samples." }
        return "At least \(count) visible \(count == 1 ? "return" : "returns") in this clip. Gaps may hide others."
    }

    private func interpretationMessage(_ value: ObservationClipReview) -> String? {
        guard value.timelineOrderIsValid else {
            return "Frame times aren't in order. Original samples are shown in extraction order; their chronology is unresolved."
        }
        let reviewedCount = value.rows.flatMap(\.samples).filter { $0.frameReview != nil }.count
        if reviewedCount > 0 {
            return "You reviewed \(reviewedCount) \(reviewedCount == 1 ? "sample" : "samples"). Your labels and unknown choices take priority; original text and model results stay available."
        }
        switch value.interpretationState {
        case .corrected:
            return "Notes were corrected. The earlier screen interpretation was removed; original samples remain."
        case .invalid:
            return "An unsupported interpretation was removed. Original samples remain."
        case .unclassified:
            return "These samples have not been interpreted."
        case .noVideo:
            return nil
        case .available:
            switch value.classificationStatus {
            case .unavailable: return "On-device recognition was unavailable. These samples remain unknown."
            case .failed: return "Recognition did not finish. These samples remain unknown."
            case .partialFailure: return "Some recognition requests failed. Unresolved samples remain visible."
            case .noEligibleFrames: return "No samples had enough complete text for recognition."
            case .completed, nil: return nil
            }
        }
    }
}

private struct ObservationMomentSelection: Identifiable {
    let id: UUID
}

private func momentLabel(_ moment: ObservationReviewMoment) -> String {
    switch moment.resolution {
    case .recognized: moment.resolvedContext?.displayName ?? "Unknown screen"
    case .ambiguous: "Ambiguous screen"
    case .conflicting: "Unresolved at this timestamp"
    case .unknown: "Unknown screen"
    }
}

private func momentCaveat(_ moment: ObservationReviewMoment) -> String? {
    if moment.samples.count > 1 {
        return "\(moment.samples.count) samples share this time; their order is unknown."
    }
    if moment.hasRequestedTimeFallback { return "Requested sample time; exact frame time unavailable." }
    guard let frame = moment.samples.first?.frame else { return nil }
    if frame.textWasTruncated { return "Text was limited; identity remains unknown." }
    switch frame.outcome {
    case .blank: return "No readable text"
    case .decodeFailed: return "Frame unavailable"
    case .ocrFailed: return "Text extraction failed"
    case .observed: return nil
    }
}

private func observationSampleTime(_ seconds: Double, fractionDigits: Int = 1) -> String {
    let scale = fractionDigits == 3 ? 1_000 : 10
    let units = Int((seconds * Double(scale)).rounded())
    // Round the whole value before splitting minutes, avoiding labels such as 00:60.0.
    return String(format: "%02d:%02d.%0*d", units / (60 * scale), (units / scale) % 60,
                  fractionDigits, units % scale)
}

@MainActor
private struct ObservationSampleDetail: View {
    @Bindable var store: MorningStore
    let acquisition: ObservationAcquisition
    let moment: ObservationReviewMoment
    let timelineOrderIsValid: Bool
    @Environment(\.dismiss) private var dismiss
    @ViewState<ScreenReviewSelection?> private var reviewSelection = nil
    @ViewState<SampleNarrationSelection?> private var narrationSelection = nil

    var body: some View {
        MorningList {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                Text(momentLabel(moment)).font(.headline)
                Text(acquisition.sourceLabel).font(.subheadline).foregroundStyle(MorningStyle.muted)
                if let caveat = momentCaveat(moment) { Text(caveat).font(.subheadline) }
                if !timelineOrderIsValid {
                    Text("Frame times aren't in order. This source's chronology remains unresolved.")
                        .font(.subheadline).foregroundStyle(MorningStyle.muted)
                }
                Text("A visual label is a proposal about what's visible. It doesn't establish which app was open or what you did.")
                    .font(.caption).foregroundStyle(MorningStyle.muted)
                Text("Times are offsets into this recording, rounded to a millisecond.")
                    .font(.caption).foregroundStyle(MorningStyle.muted)
                }.padding(.vertical, 4)
            }
            ForEach(Array(moment.samples.enumerated()), id: \.element.id) { index, sample in
                Section {
                    sampleTime("Requested sample", value: observationSampleTime(sample.frame.requestedTimeSeconds, fractionDigits: 3),
                               identifier: "observation.sample.requestedTime.\(sample.id.uuidString)")
                    sampleTime("Actual frame", value: sample.frame.actualTimeSeconds.map { observationSampleTime($0, fractionDigits: 3) } ?? "Unavailable",
                               identifier: "observation.sample.actualTime.\(sample.id.uuidString)")
                    let userReview = acquisition.frameReviews.first { $0.sampleID == sample.id }
                    let originalDecision = acquisition.classification?.decisions.first { $0.sampleID == sample.id }
                    if let userReview {
                        LabeledContent("Your label", value: userReview.label ?? "Unknown screen")
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Your label")
                            .accessibilityValue(userReview.label ?? "Unknown screen")
                            .accessibilityIdentifier("observation.sample.userLabel.\(sample.id.uuidString)")
                        Text(userReview.label == nil
                             ? "You kept this screen unknown. It is left out of later activity suggestions."
                             : "Your description stays separate from the model's interpretation.")
                            .font(.caption).foregroundStyle(MorningStyle.muted)
                    }
                    if case .identified(let context, _) = originalDecision?.evidence {
                        LabeledContent(userReview == nil ? "Proposed visual label" : "Original proposed label", value: context.displayName)
                    } else if case .ambiguous = originalDecision?.evidence {
                        Text("The original interpretation supported more than one possible context.")
                            .font(.subheadline).foregroundStyle(MorningStyle.muted)
                    }
                    if let quote = originalDecision?.evidenceQuote ?? userReview?.evidenceQuote ?? sample.quote {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Exact evidence quote").font(.caption.weight(.semibold)).foregroundStyle(MorningStyle.muted)
                            Text(quote).font(.subheadline).textSelection(.enabled)
                                .accessibilityIdentifier("observation.sample.quote.\(sample.id.uuidString)")
                        }
                        narrationAction(quote: quote, sampleID: sample.id,
                            identifier: "observation.sample.readMoment.\(sample.id.uuidString)")
                    } else {
                        Text("No original interpretation quote is attached to this sample.")
                            .font(.caption).foregroundStyle(MorningStyle.muted)
                    }
                    if let reviewedQuote = userReview?.evidenceQuote,
                       let originalQuote = originalDecision?.evidenceQuote,
                       !reviewedQuote.utf8.elementsEqual(originalQuote.utf8) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Excerpt you selected").font(.caption.weight(.semibold)).foregroundStyle(MorningStyle.muted)
                            Text(reviewedQuote).font(.subheadline).textSelection(.enabled)
                                .accessibilityIdentifier("observation.sample.userQuote.\(sample.id.uuidString)")
                        }
                        narrationAction(quote: reviewedQuote, sampleID: sample.id,
                            identifier: "observation.sample.readReviewedMoment.\(sample.id.uuidString)")
                    }
                    if acquisition.correctedText == nil {
                        Button(userReview == nil ? "Correct label" : "Edit your label") {
                            reviewSelection = .init(id: sample.id, acquisition: acquisition)
                        }
                        .disabled(store.busy || store.sessionActive || !store.storageIsAvailable)
                        .accessibilityIdentifier("observation.sample.correctLabel.\(sample.id.uuidString)")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Original extracted text").font(.caption.weight(.semibold)).foregroundStyle(MorningStyle.muted)
                        Text(sample.frame.text.isEmpty ? "No readable text was retained." : sample.frame.text)
                            .font(.subheadline).textSelection(.enabled)
                            .accessibilityIdentifier("observation.sample.originalText.\(sample.id.uuidString)")
                    }
                    if sample.frame.textWasTruncated {
                        Text("This text was limited during extraction and cannot support a screen identity.")
                            .font(.caption).foregroundStyle(MorningStyle.muted)
                    }
                    ForEach(Array(sample.frame.warnings.enumerated()), id: \.offset) { _, warning in
                        Text(warning).font(.caption).foregroundStyle(MorningStyle.muted)
                    }
                } header: {
                    Text(moment.samples.count == 1 ? "Source sample" : "Source sample \(index + 1)")
                }
            }
        }
        .scrollContentBackground(.hidden).background(MorningStyle.background)
        .navigationTitle("Sampled moment")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.accessibilityIdentifier("observation.sample.close")
            }
        }
        .sheet(item: $reviewSelection) { selected in
            ObservationScreenReviewView(store: store, acquisition: selected.acquisition, sampleID: selected.id)
        }
        .sheet(item: $narrationSelection) { selected in
            ObservationNarrationView(store: store, observationID: acquisition.id,
                requestedNarration: selected.prepared)
        }
    }

    @ViewBuilder private func narrationAction(quote: String, sampleID: UUID, identifier: String) -> some View {
        if let prepared = try? ObservationNarrationComposer.prepare(acquisition: acquisition,
            frameID: sampleID, quote: quote) {
            Button {
                narrationSelection = .init(prepared: prepared)
            } label: {
                Label("Read this saved moment", systemImage: "speaker.wave.2")
            }
            .buttonStyle(.borderless)
            .disabled(store.busy || store.sessionActive || !store.storageIsAvailable || store.voiceInputBlocksPlayback)
            .accessibilityIdentifier(identifier)
        }
    }

    private func sampleTime(_ title: String, value: String, identifier: String) -> some View {
        LabeledContent(title, value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title).accessibilityValue(value)
            .accessibilityIdentifier(identifier)
    }
}

/// Resolves a weekly citation directly, without waiting for an off-screen List row
/// to mount. Only source IDs survive navigation; edits/deletion replace the view.
struct ObservationSampleSourceView: View {
    @Bindable var store: MorningStore
    let acquisitionID: UUID
    let sampleID: UUID
    var managesEntryOccupancy = true

    var body: some View {
        Group {
            if let acquisition = store.observationArchive.entry(id: acquisitionID),
               let review = try? ObservationClipReview(acquisition: acquisition),
               let moment = review.rows.first(where: { $0.samples.contains { $0.id == sampleID } }) {
                ObservationSampleDetail(store: store, acquisition: acquisition, moment: moment, timelineOrderIsValid: review.timelineOrderIsValid)
            } else {
                ContentUnavailableView("Sample changed", systemImage: "doc.text.magnifyingglass",
                    description: Text("Return to observations to see the current evidence."))
                    .navigationTitle("Sampled moment")
            }
        }
        .onAppear { if managesEntryOccupancy { store.observationDetailPresented = true } }
        .onDisappear { if managesEntryOccupancy { store.observationDetailPresented = false } }
    }
}

private struct ScreenReviewSelection: Identifiable {
    let id: UUID
    let acquisition: ObservationAcquisition
}

/// Keeps the exact prepared reference while presenting, not a mutable selected-line index.
private struct SampleNarrationSelection: Identifiable {
    let id = UUID()
    let prepared: PreparedObservationNarration
}
