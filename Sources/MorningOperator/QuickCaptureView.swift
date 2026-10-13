import SwiftUI
import MorningCore
import MorningApple

extension QuickCaptureKind {
    var symbol: String {
        switch self {
        case .dream: "moon.stars"
        case .thought: "lightbulb"
        case .reminder: "checklist"
        case .calendarIdea: "calendar"
        }
    }
    var shortTitle: String { self == .calendarIdea ? "Calendar" : displayName }
}

struct CapturesView: View {
    @Bindable var store: MorningStore
    @ViewState<QuickCaptureKind?> private var filter = nil
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeading(eyebrow: "Keep a little spark", title: "Before it slips away.",
                            subtitle: "A dream. An idea. Something for later. Give it a place to land.")
                Button { store.openCapture() } label: {
                    HStack {
                        Image(systemName: "plus").font(.title3)
                        Text("What's on your mind?").font(.headline)
                        Spacer()
                        Image(systemName: "square.and.pencil")
                    }.padding(24).foregroundStyle(.primary)
                        .background(MorningStyle.paleOrange.opacity(0.7), in: RoundedRectangle(cornerRadius: 26))
                }.buttonStyle(.plain).accessibilityIdentifier("capture.open")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        filterChip(nil)
                        ForEach(QuickCaptureKind.allCases, id: \.self) { filterChip($0) }
                    }
                }
                let items = store.captures.filter { filter == nil || $0.kind == filter }
                if items.isEmpty {
                    EmptyMoment(symbol: filter?.symbol ?? "sparkles", title: filter == .dream ? "A home for your dreams." : "Room for a new idea.",
                        detail: "Write it here, use your keyboard's dictation, or ask Siri to capture it with MORE.")
                } else {
                    ForEach(items) { capture in
                        Card {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label(capture.kind.shortTitle, systemImage: capture.kind.symbol).font(.caption.weight(.semibold))
                                        .foregroundStyle(MorningStyle.accent)
                                    Spacer()
                                    Text(capture.createdAt.formatted(.dateTime.month(.abbreviated).day())).font(.caption).foregroundStyle(MorningStyle.muted)
                                }
                                Text(capture.text).font(.body).textSelection(.enabled)
                                if capture.source == .voice {
                                    Label("Spoken with MORE", systemImage: "waveform")
                                        .font(.caption).foregroundStyle(MorningStyle.muted)
                                        .accessibilityIdentifier("capture.spokenSource")
                                }
                                if let date = capture.requestedDate {
                                    Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                                        .font(.caption).foregroundStyle(MorningStyle.muted)
                                }
                                if store.receipts[capture.id.uuidString] != nil {
                                    Label("Added to Apple \(capture.kind == .reminder ? "Reminders" : "Calendar")", systemImage: "checkmark.circle")
                                        .font(.caption).foregroundStyle(MorningStyle.green)
                                } else if store.pendingCaptures[capture.id.uuidString] != nil {
                                    Text("Save unconfirmed · check the Apple app before retrying").font(.caption).foregroundStyle(.orange)
                                } else if capture.kind == .reminder || capture.kind == .calendarIdea {
                                    Text("Saved as a note · no system item scheduled").font(.caption).foregroundStyle(MorningStyle.muted)
                                }
                            }
                        }
                    }
                }
                if let notice = store.notice { NoticeView(text: notice, dismiss: { store.notice = nil }) }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
    }
    private func filterChip(_ kind: QuickCaptureKind?) -> some View {
        Button { filter = kind } label: {
            Text(kind?.shortTitle ?? "All").font(.subheadline.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(filter == kind ? MorningStyle.lavender : MorningStyle.surface, in: Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier("capture.filter.\(kind?.rawValue ?? "all")").accessibilityAddTraits(filter == kind ? .isSelected : [])
    }
}

struct QuickCaptureView: View {
    @Bindable var store: MorningStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var textFocused: Bool
    @ViewState<String> private var text = ""
    @ViewState<QuickCaptureKind> private var kind = .thought
    @ViewState<Date> private var date = Date().addingTimeInterval(4 * 3600)
    @ViewState<Bool> private var hasDate = false
    @ViewState<Bool> private var saveToSystem = true
    @ViewState<Int> private var duration = 30
    @ViewState<String?> private var explanation = nil
    @ViewState<String?> private var lastInterpretedText = nil
    @ViewState<UUID> private var captureID = UUID()
    @ViewState<QuickCaptureSource> private var source: QuickCaptureSource = .typed
    private var isSchedule: Bool { kind == .reminder || kind == .calendarIdea }
    private var buttonTitle: String {
        if isSchedule && saveToSystem { return kind == .reminder ? "Add to Reminders" : "Add to Calendar" }
        return kind == .dream ? "Save my dream" : "Save thought"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Catch the thought.").font(.system(.largeTitle, design: .serif, weight: .medium))
                    HStack(spacing: 6) {
                        ForEach(QuickCaptureKind.allCases, id: \.self) { option in
                            Button { kind = option } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: option.symbol).font(.title3)
                                    Text(option.shortTitle).font(.caption)
                                }.frame(maxWidth: .infinity).padding(.vertical, 15)
                                    .background(kind == option ? MorningStyle.lavender : MorningStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                            }.buttonStyle(.plain).accessibilityIdentifier("capture.kind.\(option.rawValue)").accessibilityAddTraits(kind == option ? .isSelected : [])
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What's on your mind?").font(.subheadline.weight(.medium))
                        TextEditor(text: $text).font(.body).scrollContentBackground(.hidden)
                            .frame(minHeight: 160).padding(14)
                            .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                            .accessibilityLabel("Capture text").accessibilityIdentifier("capture.text").focused($textFocused)
                        Button { interpret() } label: { Label("Find a reminder or time", systemImage: "sparkles") }
                            .font(.subheadline).buttonStyle(.borderless).disabled(text.isEmpty)
                    }
                    if isSchedule {
                        VStack(alignment: .leading, spacing: 18) {
                            Toggle("Add to Apple \(kind == .reminder ? "Reminders" : "Calendar")", isOn: $saveToSystem)
                            if kind == .reminder { Toggle("Set a time & alert", isOn: $hasDate) }
                            if hasDate || kind == .calendarIdea {
                                DatePicker(kind == .reminder ? "Remind me" : "Starts", selection: $date)
                                    .datePickerStyle(.compact)
                                Text(TimeZone.current.identifier).font(.caption).foregroundStyle(MorningStyle.muted)
                            }
                            if kind == .calendarIdea {
                                Stepper("\(duration) minutes", value: $duration, in: 5...240, step: 5)
                            }
                            if let explanation { Text(explanation).font(.caption).foregroundStyle(MorningStyle.muted) }
                        }.font(.subheadline).padding(20).background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                    }
                    Text(isSchedule && saveToSystem ? "Review the text and time. Saving adds one item to your default Apple \(kind == .reminder ? "Reminders list" : "calendar"). Your Apple account may sync it to other devices." : "Saved privately in Morning Operator on this device.")
                        .font(.caption).foregroundStyle(MorningStyle.muted)
                    if let notice = store.notice { NoticeView(text: notice, dismiss: { store.notice = nil }) }
                }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.background(MorningStyle.background)
                .safeAreaInset(edge: .bottom) {
                    Button {
                        Task {
                            if await store.saveCapture(kind: kind, text: text,
                                date: hasDate || kind == .calendarIdea ? date : nil, duration: duration,
                                saveToSystem: isSchedule && saveToSystem, id: captureID, source: source) { dismiss() }
                        }
                    } label: {
                        HStack { if store.captureBusy { ProgressView() }; Text(buttonTitle).frame(maxWidth: .infinity) }
                            .padding(.vertical, 8)
                    }.buttonStyle(.glassProminent).tint(MorningStyle.controlTint).controlSize(.large)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.captureBusy)
                        .accessibilityIdentifier("capture.save")
                        .padding(24).background(MorningStyle.background)
                }
                #if os(iOS)
                .toolbar { ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { textFocused = false }.accessibilityIdentifier("input.done")
                } }
                #endif
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("capture.cancel").disabled(store.captureBusy)
                } }
        }
        .interactiveDismissDisabled(store.captureBusy)
        .presentationDragIndicator(.visible)
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 700)
        #endif
        .onAppear {
            store.notice = nil
            text = store.capturePrefill
            source = store.captureSource
            if !text.isEmpty { interpret() }
        }
    }

    private func interpret() {
        guard text != lastInterpretedText else { return }
        let parsed = CaptureRequestParser.parse(text)
        switch parsed.destination {
        case .thought: kind = .thought
        case .dream: kind = .dream
        case .reminder: kind = .reminder
        case .calendar: kind = .calendarIdea
        }
        text = parsed.content
        lastInterpretedText = text
        if let proposed = parsed.suggestedDate { date = proposed; hasDate = true }
        else { hasDate = false }
        explanation = parsed.dateExplanation
        if parsed.needsDateReview && parsed.suggestedDate == nil {
            explanation = "Choose the date and time you meant before saving."
        }
    }
}
