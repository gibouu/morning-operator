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
    @ViewState<Bool> private var explainingLocation = false
    @ViewState<UUID?> private var previewAttempt = nil
    @ViewState<PreparedMorningBriefing?> private var playingPreview = nil
    @ViewState<Bool> private var addedToMorning = false
    @FocusState private var cityFocused: Bool
    private var controller: MorningBriefingController { store.briefing }

    var body: some View {
        NavigationStack {
          ScrollViewReader { proxy in
            MorningForm {
                Section {
                    Text("Choose what you'd like to hear in your morning.")
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                }
                if store.usesSyntheticBriefing {
                    Section { Text("Synthetic test sources · not your calendar or weather")
                        .font(.raleway(.caption)).accessibilityIdentifier("briefing.synthetic") }
                }
                if let issue = controller.settingsRecoveryError {
                    Section {
                        Text(issue)
                        Button("Reset Your day settings", role: .destructive) { confirmingReset = true }
                            .disabled(store.sessionActive)
                    }
                } else {
                    calendarSection.disabled(store.sessionActive)
                    healthSection
                    weatherSection
                    MorningExtrasSettingsSection(store: store)
                    recapSection
                }
                if let error = controller.errorMessage {
                    Section { Text(error).font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("briefing.error") }
                }
                Section {
                  DisclosureGroup(MorningPermissionSetup.text("About this recap", "À propos du récapitulatif")) {
                    Text("MORE prepares this recap when you open the app and checks it again before speaking. Overnight preparation isn't guaranteed.")
                    Text(MorningPermissionSetup.text("Only your chosen sources are used. Health stays local unless you start the optional online conversation. MORE never changes your Health records.", "Seules vos sources choisies sont utilisées. Santé reste local sauf si vous démarrez la conversation en ligne facultative. MORE ne modifie jamais vos données Santé."))
                  }
                }.font(.raleway(.caption2)).foregroundStyle(MorningStyle.muted)
            }
            .scrollContentBackground(.hidden).background(MorningPaper(showsSun: false))
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
            .alert(MorningPermissionSetup.text("The weather, where you are", "La météo, là où vous êtes"), isPresented: $explainingLocation) {
                Button(MorningPermissionSetup.text("Allow location", "Autoriser la localisation")) {
                    Task { _ = await controller.enableCurrentLocation(); await store.prepareDayIfConfigured() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(MorningPermissionSetup.text("While MORE is open, an approximate position brings local weather and a sky that follows the sun. Coordinates are sent to Apple Weather and stay out of your saved history.", "Quand MORE est ouvert, une position approximative apporte la météo locale et un ciel qui suit le soleil. Les coordonnées sont transmises à Apple Météo et ne sont pas enregistrées dans votre historique."))
            }
            .confirmationDialog("Reset Your day settings?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset sources", role: .destructive) {
                    if !store.sessionActive { try? controller.resetSettings() }
                }
                Button("Cancel", role: .cancel) { }
            } message: { Text(MorningPermissionSetup.text("This removes your calendar, city and sleep choices from MORE. Your routine and Apple app data stay in place.", "Ceci retire vos choix de calendriers, de ville et de sommeil dans MORE. Votre routine et vos données Apple sont conservées.")) }
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
                Button(controller.isCalendarAuthorized ? String(localized: "Choose calendars", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Connect Calendar", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)) {
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
                            Text(choice.sourceTitle).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        }
                    }.accessibilityIdentifier("briefing.calendar.\(choice.id)")
                }
            }
            if !controller.settings.calendarIDs.isSubset(of: Set(controller.calendarChoices.map(\.id))) {
                Text("Some selected calendars aren't available. Choose them again or clear the selection.")
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                Button("Clear calendar selection") {
                    var settings = controller.settings; settings.calendarIDs = []; save(settings)
                }
            }
        } header: { Text("Your calendar") } footer: {
            Text("Apple requires full calendar access to read events. MORE reads only the calendars you select; this recap doesn't change them.")
                .font(.raleway(.caption2))
        }
    }

    private var healthSection: some View {
        MorningHealthSection(store: store, stopPreview: stopPreview)
    }

    private var recapSection: some View {
        Section {
            if controller.isPreparing { ProgressView(MorningPermissionSetup.text("Preparing your recap…", "Préparation du récapitulatif…")) }
            if let document = controller.prepared { MorningBriefingDocumentView(document: document) }
            Button("Refresh recap") {
                stopPreview()
                Task { _ = await controller.refresh(force: true) }
            }.disabled(controller.isPreparing).accessibilityIdentifier("briefing.refresh")
            Button("Hear this recap") { hearRecap() }
                .disabled(store.sessionActive || controller.isPreparing || controller.prepared?.hasUsableFacts != true)
                .accessibilityIdentifier("briefing.hear")
            if store.routine != nil {
                let alreadyAdded = store.routine?.steps.contains(where: { $0.automation == .morningBriefing }) == true
                Button(alreadyAdded ? String(localized: "Already in your morning", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Add to my morning", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)) {
                    addedToMorning = store.addBriefingToRoutine()
                }.disabled(store.sessionActive || alreadyAdded).accessibilityIdentifier("briefing.addToRoutine")
                if addedToMorning { Text("Added as a draft. Review and approve your routine.").accessibilityIdentifier("briefing.saved") }
            }
        } header: { Text(MorningPermissionSetup.text("Your recap", "Votre récapitulatif")) }
    }

    private func hearRecap() {
        stopPreview()
        guard !store.sessionActive else { return }
        let attempt = UUID()
        previewAttempt = attempt
        Task {
            guard let document = await controller.refresh(), previewAttempt == attempt,
                  !store.sessionActive, !store.privacyBlocksWork, scenePhase == .active,
                  controller.permitsPlayback(of: document), document.hasUsableFacts else { return }
            playingPreview = document
            do { try await store.speech.speakAndWait(document.spokenText) }
            catch { /* Speech interruptions are handled by the ordinary controls. */ }
            if previewAttempt == attempt { playingPreview = nil; previewAttempt = nil }
        }
    }

    private var weatherSection: some View {
        Section {
            Group {
                Picker(MorningPermissionSetup.text("Weather location", "Position météo"), selection: Binding(get: { controller.settings.usesCurrentLocation }, set: { current in
                    var settings = controller.settings; settings.usesCurrentLocation = current; save(settings)
                })) {
                    Text(MorningPermissionSetup.text("Current location", "Position actuelle")).tag(true)
                    Text(MorningPermissionSetup.text("Choose a city", "Choisir une ville")).tag(false)
                }.accessibilityIdentifier("briefing.locationSource")
                if controller.settings.usesCurrentLocation {
                    if let location = controller.currentWeatherLocation {
                        LabeledContent(MorningPermissionSetup.text("Location", "Position"), value: location.displayName)
                            .accessibilityIdentifier("briefing.currentLocation")
                    }
                    if let issue = controller.locationIssue { Text(issue).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted) }
                    Button(controller.locationAuthorization == .notDetermined
                        ? MorningPermissionSetup.text("Allow location", "Autoriser la localisation")
                        : MorningPermissionSetup.text("Update my location", "Actualiser ma position")) {
                        if controller.locationAuthorization == .notDetermined { explainingLocation = true }
                        else { Task { _ = await controller.enableCurrentLocation(requestPermission: false); await store.prepareDayIfConfigured() } }
                    }.accessibilityIdentifier("briefing.useCurrentLocation")
                    if controller.locationAuthorization == .denied {
                        Button(MorningPermissionSetup.text("Open iPhone Settings", "Ouvrir les réglages de l’iPhone")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                } else if let city = controller.settings.weatherLocation {
                    LabeledContent("City", value: city.displayName).accessibilityIdentifier("briefing.city")
                }
                if controller.currentWeatherLocation != nil {
                    Picker("Temperature", selection: Binding(get: { controller.settings.temperatureUnit }, set: { unit in
                        var settings = controller.settings; settings.temperatureUnit = unit; save(settings)
                    })) {
                        Text("Celsius").tag(MorningBriefingTemperatureUnit.celsius)
                        Text("Fahrenheit").tag(MorningBriefingTemperatureUnit.fahrenheit)
                    }.accessibilityIdentifier("briefing.temperatureUnit")
                    Button("Remove weather") {
                        var settings = controller.settings; settings.weatherLocation = nil; settings.usesCurrentLocation = false; save(settings)
                    }.accessibilityIdentifier("briefing.removeWeather")
                }
                if !controller.settings.usesCurrentLocation {
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
                                        Text(suggestion.subtitle).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
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
                        Text(outcome == .noMatch ? AppLanguage.localized("No matching cities. Try a nearby city or include the country.")
                             : WeatherObservationError.searchUnavailable.moreDescription)
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    }
                }
            }.disabled(store.sessionActive)
            if let snapshot = controller.currentWeatherSnapshot {
                currentWeatherDetails(snapshot)
                MorningWeatherAttributionView(attribution: snapshot.attribution, synthetic: store.usesSyntheticBriefing)
            }
        } header: { Text("Weather · optional") } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(MorningPermissionSetup.text("With your permission, MORE uses your position only while open. An approximate location is enough. A city search goes to Apple Maps; your weather location goes to Apple Weather. Your current coordinates aren't saved in your history.", "Avec votre accord, MORE utilise votre position uniquement quand l’app est ouverte. Une position approximative suffit. La recherche de ville passe par Apple Plans ; la position météo est transmise à Apple Météo. Vos coordonnées actuelles ne sont pas enregistrées dans votre historique."))
                Text(MorningThemeClock.shared.solarSourceDescription)
                    .accessibilityIdentifier("briefing.solarSource")
            }.font(.raleway(.caption2))
        }
    }

    @ViewBuilder private func currentWeatherDetails(_ weather: WeatherObservationSnapshot) -> some View {
        LabeledContent(weather.localizedConditionDescription(), value: temperature(weather.temperatureCelsius))
        if let value = weather.apparentTemperatureCelsius {
            LabeledContent(MorningPermissionSetup.text("Feels like", "Ressenti"), value: temperature(value))
        }
        if let value = weather.windSpeedMetersPerSecond {
            LabeledContent(MorningPermissionSetup.text("Wind", "Vent"), value: number(value * 3.6) + " km/h")
        }
        if let value = weather.windGustMetersPerSecond {
            LabeledContent(MorningPermissionSetup.text("Gusts", "Rafales"), value: number(value * 3.6) + " km/h")
        }
        if let value = weather.windDirectionDegrees {
            LabeledContent(MorningPermissionSetup.text("Wind from", "Vent venant de"), value: number(value) + "°")
        }
        if let value = weather.precipitationIntensityMillimetersPerHour {
            LabeledContent(MorningPermissionSetup.text("Precipitation", "Précipitations"), value: number(value) + " mm/h")
        }
        if let value = weather.cloudCover {
            LabeledContent(MorningPermissionSetup.text("Cloud cover", "Couverture nuageuse"), value: number(value * 100) + " %")
        }
        if let value = weather.humidity {
            LabeledContent(MorningPermissionSetup.text("Humidity", "Humidité"), value: number(value * 100) + " %")
        }
        if let value = weather.visibilityMeters {
            LabeledContent(MorningPermissionSetup.text("Visibility", "Visibilité"), value: number(value / 1_000) + " km")
        }
        if let value = weather.dewPointCelsius {
            LabeledContent(MorningPermissionSetup.text("Dew point", "Point de rosée"), value: temperature(value))
        }
        if let value = weather.uvIndex { LabeledContent("UV", value: String(value)) }
        if let value = weather.pressureHectopascals {
            LabeledContent(MorningPermissionSetup.text("Pressure", "Pression"), value: number(value) + " hPa")
        }
        if let value = weather.isDaylight {
            LabeledContent(MorningPermissionSetup.text("Sky", "Ciel"), value: value
                ? MorningPermissionSetup.text("Day", "Jour") : MorningPermissionSetup.text("Night", "Nuit"))
        }
        Text(weather.observationAt, format: .dateTime.hour().minute())
            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
    }
    private func number(_ value: Double) -> String {
        value.formatted(.number.locale(AppLanguage.locale).precision(.fractionLength(0...1)))
    }
    private func temperature(_ celsius: Double) -> String {
        controller.settings.temperatureUnit == .fahrenheit
            ? number(celsius * 9 / 5 + 32) + " °F" : number(celsius) + " °C"
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
        var settings = controller.settings; settings.weatherLocation = city; settings.usesCurrentLocation = false; save(settings)
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

    private func stopPreview() {
        let ownedPreview = previewAttempt != nil || playingPreview != nil
        previewAttempt = nil; playingPreview = nil
        if ownedPreview && !store.sessionActive { store.speech.stop() }
    }
}

struct MorningBriefingDocumentView: View {
    let document: PreparedMorningBriefing
    var operation: RoutineStepAutomation? = .morningBriefing

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if document.hasUsableFacts {
                Text(MorningAppStepExecutor.text(for: operation, in: document))
                    .textSelection(.enabled).accessibilityIdentifier("briefing.text")
            }
            Text("Prepared \(document.preparedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLanguage.locale)))")
                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted).accessibilityIdentifier("briefing.preparedAt")
            if !document.isCurrent(at: Date(), timeZoneIdentifier: TimeZone.current.identifier) {
                Text("This recap needs an update before playback.").font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
            }
            if document.calendar.status != .notConfigured { source(AppLanguage.localized("Calendar"), section: document.calendar, isCalendar: true) }
            if operation != .todayCalendar, document.weather.status != .notConfigured {
                source(AppLanguage.localized("Weather"), section: document.weather, isCalendar: false)
            }
            if operation != .todayCalendar, document.sleep.status != .notConfigured {
                MorningSleepDetailsView(section: document.sleep)
            }
        }
    }

    private func source(_ name: String, section: MorningBriefingSection, isCalendar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(isCalendar || section.status != .fresh ? "\(name) · \(section.statusText)" : name)
                .font(.raleway(.caption))
            if isCalendar, !section.sourceLabels.isEmpty {
                Text(section.sourceLabels.joined(separator: " · ")).font(.raleway(.caption2))
            }
            if let retrievedAt = section.retrievedAt {
                Text(isCalendar ? String(localized: "Local read at \(retrievedAt.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(AppLanguage.locale)))", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Retrieved at \(retrievedAt.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(AppLanguage.locale)))", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)).font(.raleway(.caption2))
            }
            if let observedAt = section.observationAt {
                Text("Conditions at \(observedAt.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(AppLanguage.locale)))").font(.raleway(.caption2))
            }
        }.foregroundStyle(MorningStyle.muted)
    }
}

/// Source categories are inferred from HealthKit metadata, never personal source IDs.
struct MorningSleepDetailsView: View {
    let section: MorningBriefingSection

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(section.status == .fresh ? section.segments.map(\.text).joined(separator: " ") : section.statusText)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("briefing.sleep")
            if !section.sourceLabels.isEmpty {
                Text(section.sourceLabels.joined(separator: " · "))
                    .font(.caption).accessibilityIdentifier("briefing.sleepSources")
            }
            if let readAt = section.retrievedAt {
                Text(MorningPermissionSetup.text("Read locally: ", "Lecture locale : ") + readAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLanguage.locale)))
                    .font(.caption2)
            }
            Text(MorningPermissionSetup.text("Overlapping records count once. The union can differ from Apple Health’s source priority.", "Les enregistrements qui se chevauchent sont comptés une seule fois. Le total peut différer de Santé Apple, qui applique sa priorité de sources."))
                .font(.caption2)
        }.foregroundStyle(MorningStyle.muted)
    }
}

/// Provider credit lives with the weather connection settings.
struct MorningWeatherAttributionView: View {
    let attribution: WeatherAttributionInfo
    var synthetic = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if synthetic {
                Text("Synthetic weather attribution").font(.raleway(.caption))
            } else {
                AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit().frame(height: 18)
                    case .failure: Text("Apple Weather mark unavailable").font(.raleway(.caption))
                    default: ProgressView().accessibilityLabel("Loading Apple Weather mark")
                    }
                }
                .frame(maxWidth: 150, alignment: .leading)
                .accessibilityLabel("Apple Weather")
            }
            Link("Weather data sources", destination: attribution.legalURL).font(.raleway(.caption))
                .accessibilityIdentifier("weather.sources")
        }
    }
}
