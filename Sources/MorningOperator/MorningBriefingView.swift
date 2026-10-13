import SwiftUI
import MorningCore
import MorningApple

/// Connection choices live in Review. The everyday morning remains one page.
struct MorningBriefingView: View {
    @Bindable var store: MorningStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState<String> private var cityQuery = ""
    @ViewState<Bool> private var confirmingReset = false
    @ViewState<String?> private var savedMessage = nil
    @ViewState<UUID?> private var previewAttempt = nil
    @ViewState<PreparedMorningBriefing?> private var playingPreview = nil
    @FocusState private var cityFocused: Bool
    private var controller: MorningBriefingController { store.briefing }

    var body: some View {
        NavigationStack {
          ScrollViewReader { proxy in
            MorningForm {
                Section {
                    Text("A little context.\nA calmer start.").font(.title2.weight(.semibold))
                    Text("Choose what you'd like to hear before the rest of your morning.")
                        .foregroundStyle(MorningStyle.muted)
                }
                if store.usesSyntheticBriefing {
                    Section { Text("Synthetic test sources · not your calendar or weather")
                        .font(.caption).accessibilityIdentifier("briefing.synthetic") }
                }
                if let issue = controller.settingsRecoveryError {
                    Section {
                        Text(issue)
                        Button("Reset Your day settings", role: .destructive) { confirmingReset = true }
                            .disabled(store.sessionActive)
                    }
                } else {
                    calendarSection.disabled(store.sessionActive)
                    weatherSection.disabled(store.sessionActive)
                    previewSection
                    routineSection
                }
                if let error = controller.errorMessage {
                    Section { Text(error).font(.footnote).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("briefing.error") }
                }
                Section {
                    Text("MORE prepares this recap when you open the app and checks it again before speaking. Overnight preparation isn't guaranteed.")
                    Text("This recap uses your selected calendar and current weather. It doesn't change your events.")
                }.font(.caption).foregroundStyle(MorningStyle.muted)
            }
            .scrollContentBackground(.hidden).background(MorningStyle.background)
            // Keep the city field and its suggestions above the keyboard.
            .onChange(of: cityFocused) { _, focused in if focused { scrollToCitySearch(proxy) } }
            .onChange(of: controller.citySuggestions) { _, _ in if cityFocused { scrollToCitySearch(proxy) } }
            .navigationTitle("Your day").navigationBarTitleDisplayMode(.inline)
            // No keyboard accessory bar: it covered the city suggestions. Choosing a
            // city, Search, or dragging the form closes the keyboard.
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .disabled(store.privacyBlocksWork)
            .task {
                if controller.isCalendarAuthorized { await controller.requestCalendarAccess() }
                await store.prepareDayIfConfigured()
            }
            .onChange(of: store.speech.state) { _, state in
                if state == .idle { playingPreview = nil; previewAttempt = nil }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { stopPreview() }
            }
            .onDisappear {
                stopPreview()
                controller.clearCitySearch()
            }
            .confirmationDialog("Reset Your day settings?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset sources", role: .destructive) {
                    if !store.sessionActive { try? controller.resetSettings() }
                }
                Button("Cancel", role: .cancel) { }
            } message: { Text("This removes your selected calendars and city from MORE. Your routine and Apple app data stay in place.") }
          }
        }
        // The sheet's own background showed beside the keyboard's rounded corners;
        // extend the screen color under the keyboard too.
        .background(MorningStyle.background.ignoresSafeArea())
        .presentationBackground(MorningStyle.background)
        .tint(MorningStyle.accent)
    }

    private var calendarSection: some View {
        Section {
            if controller.isConnectingCalendar { ProgressView("Opening your calendars…") }
            else if controller.calendarChoices.isEmpty {
                Button(controller.isCalendarAuthorized ? "Choose calendars" : "Connect Calendar") {
                    Task { await controller.requestCalendarAccess() }
                }.accessibilityIdentifier("briefing.calendarConnect")
            } else {
                ForEach(controller.calendarChoices) { choice in
                    Toggle(isOn: Binding(get: { controller.settings.calendarIDs.contains(choice.id) }, set: { selected in
                        var settings = controller.settings
                        if selected { settings.calendarIDs.insert(choice.id) } else { settings.calendarIDs.remove(choice.id) }
                        save(settings)
                    })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(choice.title)
                            Text(choice.sourceTitle).font(.caption).foregroundStyle(MorningStyle.muted)
                        }
                    }.accessibilityIdentifier("briefing.calendar.\(choice.id)")
                }
            }
            if !controller.settings.calendarIDs.isSubset(of: Set(controller.calendarChoices.map(\.id))) {
                Text("Some selected calendars aren't available. Choose them again or clear the selection.")
                    .font(.caption).foregroundStyle(MorningStyle.muted)
                Button("Clear calendar selection") {
                    var settings = controller.settings; settings.calendarIDs = []; save(settings)
                }
            }
        } header: { Text("Your calendar") } footer: {
            Text("Apple requires full calendar access to read events. MORE reads only the calendars you select; this recap doesn't change them.")
        }
    }

    private var weatherSection: some View {
        Section {
            if let city = controller.settings.weatherLocation {
                LabeledContent("City", value: city.displayName).accessibilityIdentifier("briefing.city")
                Picker("Temperature", selection: Binding(get: { controller.settings.temperatureUnit }, set: { unit in
                    var settings = controller.settings; settings.temperatureUnit = unit; save(settings)
                })) {
                    Text("Celsius").tag(MorningBriefingTemperatureUnit.celsius)
                    Text("Fahrenheit").tag(MorningBriefingTemperatureUnit.fahrenheit)
                }.accessibilityIdentifier("briefing.temperatureUnit")
                Button("Remove weather") {
                    var settings = controller.settings; settings.weatherLocation = nil; save(settings)
                }.accessibilityIdentifier("briefing.removeWeather")
            }
            HStack {
                TextField("Search for a city", text: $cityQuery).textInputAutocapitalization(.words)
                    .focused($cityFocused)
                    .submitLabel(.search).onSubmit(search)
                    .onChange(of: cityQuery) { _, text in controller.cityQueryChanged(text) }
                    .accessibilityIdentifier("briefing.citySearch")
                Button(action: search) { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search cities").accessibilityIdentifier("briefing.searchCities")
                    .disabled(cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.isSearchingCities)
            }.id(Self.citySearchAnchor)
            if controller.isSearchingCities { ProgressView("Finding cities…") }
            ForEach(controller.cityResults) { city in
                Button(city.displayName) { choose(city) }
                    .accessibilityIdentifier("briefing.cityResult.\(city.id)")
            }
            if controller.cityResults.isEmpty {
                // Five suggestions keep the list short under the field.
                ForEach(controller.citySuggestions.prefix(5)) { suggestion in
                    Button { choose(suggestion) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle).font(.caption).foregroundStyle(MorningStyle.muted)
                            }
                        }
                    }
                    .disabled(controller.isSearchingCities)
                    .accessibilityLabel(suggestion.label)
                    .accessibilityIdentifier("briefing.citySuggestion.\(suggestion.title)")
                }
            }
            if let outcome = controller.citySearchOutcome, !controller.isSearchingCities, controller.cityResults.isEmpty,
               controller.citySuggestions.isEmpty, controller.errorMessage == nil {
                Text(outcome == .noMatch ? "No matching cities. Try a nearby city or include the country."
                     : WeatherObservationError.searchUnavailable.localizedDescription)
                    .font(.caption).foregroundStyle(MorningStyle.muted)
            }
        } header: { Text("Weather · optional") } footer: {
            Text("Searches go to Apple Maps; the city you choose is sent to Apple Weather. MORE doesn't request your device location.")
        }
    }

    private var previewSection: some View {
        Section {
            if controller.isPreparing { ProgressView("Preparing your day…").accessibilityIdentifier("briefing.preparing") }
            if let document = playingPreview ?? controller.prepared {
                MorningBriefingDocumentView(document: document, synthetic: store.usesSyntheticBriefing)
                if document.hasUsableFacts {
                    Button("Hear this recap", action: hearPreview)
                        .disabled(store.sessionActive || store.voiceInputBlocksPlayback || controller.isPreparing || previewAttempt != nil || store.speech.state != .idle)
                        .accessibilityIdentifier("briefing.hear")
                    if previewAttempt != nil || store.speech.state == .speaking {
                        Button("Stop") { previewAttempt = nil; playingPreview = nil; store.speech.stop() }
                            .disabled(store.sessionActive).accessibilityIdentifier("briefing.stop")
                    }
                }
            } else if !controller.isPreparing {
                Text("Choose a calendar or city to prepare your first recap.").foregroundStyle(MorningStyle.muted)
            }
            Button("Refresh recap") { Task { _ = await controller.refresh(force: true) } }
                .disabled(!controller.hasConfiguredSources || controller.isPreparing)
                .accessibilityIdentifier("briefing.refresh")
        } header: { Text("Your recap") } footer: {
            Text("Refreshing this preview doesn't move your routine forward or change a recap already being spoken.")
        }
    }

    private var routineSection: some View {
        Section {
            if store.routine != nil {
                let exists = store.routine?.steps.contains { $0.automation == .morningBriefing } == true
                Button(exists ? "Already in your morning" : "Add to my morning") {
                    savedMessage = store.addBriefingToRoutine() ? "Added as a draft. Review and approve your morning when you're ready." : store.notice
                }.disabled(exists || store.sessionActive || !controller.hasConfiguredSources)
                    .accessibilityIdentifier("briefing.addToRoutine")
            } else {
                Text("Once you have a routine, add Your day as its opening moment.").foregroundStyle(MorningStyle.muted)
            }
            if let savedMessage { Text(savedMessage).font(.caption).accessibilityIdentifier("briefing.saved") }
        }
    }

    private static let citySearchAnchor = "briefing.citySearchRow"

    private func scrollToCitySearch(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(Self.citySearchAnchor, anchor: .top) }
    }

    /// The controller resolves and saves the city in one step. Text typed after
    /// the tap cancels the choice; it is never cleared here.
    private func choose(_ suggestion: CitySuggestion) {
        let typed = cityQuery
        Task {
            guard await controller.chooseCity(suggestion) != nil else { return }
            previewAttempt = nil; playingPreview = nil
            if !store.sessionActive { store.speech.stop() }
            if cityQuery == typed { cityQuery = ""; cityFocused = false }
            await store.prepareDayIfConfigured()
        }
    }

    private func choose(_ city: WeatherLocation) {
        var settings = controller.settings; settings.weatherLocation = city; save(settings)
        cityQuery = ""; cityFocused = false
    }

    private func search() {
        guard !cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        cityFocused = false
        Task { await controller.searchCities(cityQuery) }
    }

    private func save(_ settings: MorningBriefingSettings) {
        previewAttempt = nil; playingPreview = nil
        if !store.sessionActive { store.speech.stop() }
        do { try controller.updateSettings(settings); Task { await store.prepareDayIfConfigured() } }
        catch { /* The controller publishes its safe, actionable error. */ }
    }

    private func hearPreview() {
        guard scenePhase == .active, !store.sessionActive, !store.voiceInputBlocksPlayback, !store.privacyBlocksWork else { return }
        let attempt = UUID(), generation = store.dataGeneration
        previewAttempt = attempt
        Task {
            defer {
                if previewAttempt == attempt && playingPreview == nil { previewAttempt = nil }
            }
            guard let document = await controller.refresh(), scenePhase == .active, previewAttempt == attempt,
                  store.dataGeneration == generation, !store.privacyBlocksWork,
                  !store.sessionActive, !store.voiceInputBlocksPlayback,
                  document.isCurrent(at: Date(), timeZoneIdentifier: TimeZone.current.identifier) else { return }
            // This exact document remains visible until a deliberate refresh.
            playingPreview = document
            store.speech.speak(document.spokenText)
        }
    }

    private func stopPreview() {
        let ownedPreview = previewAttempt != nil || playingPreview != nil
        previewAttempt = nil; playingPreview = nil
        if ownedPreview && !store.sessionActive { store.speech.stop() }
    }
}

struct MorningBriefingDocumentView: View {
    let document: PreparedMorningBriefing
    var operation: RoutineStepAutomation? = .morningBriefing
    var synthetic = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if document.hasUsableFacts {
                Text(MorningAppStepExecutor.text(for: operation, in: document))
                    .textSelection(.enabled).accessibilityIdentifier("briefing.text")
            }
            Text("Prepared \(document.preparedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(MorningStyle.muted).accessibilityIdentifier("briefing.preparedAt")
            if !document.isCurrent(at: Date(), timeZoneIdentifier: TimeZone.current.identifier) {
                Text("This recap needs an update before playback.").font(.caption).foregroundStyle(MorningStyle.muted)
            }
            if document.calendar.status != .notConfigured { source("Calendar", section: document.calendar) }
            if operation != .todayCalendar, document.weather.status != .notConfigured {
                source("Weather", section: document.weather)
                if let attribution = document.weatherAttribution {
                    VStack(alignment: .leading, spacing: 6) {
                        if synthetic {
                            Text("Synthetic weather attribution").font(.caption)
                        } else {
                            AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { phase in
                                switch phase {
                                case .success(let image): image.resizable().scaledToFit().frame(height: 18)
                                case .failure: Text("Apple Weather mark unavailable").font(.caption)
                                default: ProgressView().accessibilityLabel("Loading Apple Weather mark")
                                }
                            }
                            .frame(maxWidth: 150, alignment: .leading)
                            .accessibilityLabel("Apple Weather")
                        }
                        Link("Weather data sources", destination: attribution.legalURL).font(.caption)
                    }
                }
            }
        }
    }

    private func source(_ name: String, section: MorningBriefingSection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(name) · \(section.statusText)").font(.caption)
            if !section.sourceLabels.isEmpty { Text(section.sourceLabels.joined(separator: " · ")).font(.caption2) }
            if let retrievedAt = section.retrievedAt {
                Text("\(name == "Calendar" ? "Local read" : "Retrieved") at \(retrievedAt.formatted(date: .omitted, time: .standard))").font(.caption2)
            }
            if let observedAt = section.observationAt {
                Text("Conditions at \(observedAt.formatted(date: .omitted, time: .standard))").font(.caption2)
            }
        }.foregroundStyle(MorningStyle.muted)
    }
}
