#if MORE_JURY_DEMO
import Foundation
import MorningCore
import Observation
import SwiftUI

/// Owns the real, visible page; the ordinary browser policy still decides whether
/// a spoken request may run. No likes, stories or inferred playback are reported.
@MainActor @Observable
final class JuryDemoBrowser {
    var controller: WebMorningController?
    var url: URL?
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var revision = UUID()

    func open(_ url: URL) {
        guard let site = WebMorningSite(url: url), site.table.tasks.contains(.nextVideo) else { return }
        operation?.cancel(); operation = nil; revision = UUID()
        controller?.retire()
        controller = WebMorningController(site: site, initialURL: url)
        self.url = url
        // WebMorningView starts navigation only when this retained page is visible.
    }

    func close() {
        operation?.cancel(); operation = nil; revision = UUID()
        controller?.retire(); controller = nil; url = nil
        onClose?()
    }

    /// Returns false for ordinary conversation and routine commands. Feedback is
    /// based on the actual controller result, including login/loading refusals.
    func handle(_ text: String, feedback: @escaping (String) -> Void) -> Bool {
        guard let controller, let command = JuryDemoBrowserCommand.parse(text) else { return false }
        switch command {
        case .close:
            close()
            feedback(localized("On revient à ton matin.", "Back to your morning."))
        case .previousVideo:
            // The shared action table has no previous-video operation.
            feedback(localized("Je ne peux pas revenir à la vidéo précédente dans cette page.",
                               "I cannot return to the previous video on this page."))
        case .nextVideo:
            guard controller.actionsEnabled else {
                feedback(localized("Reviens au navigateur de MORE pour faire défiler.",
                                   "Return to the MORE browser to scroll."))
                return true
            }
            guard operation == nil else {
                feedback(localized("Je termine le défilement en cours.", "I am finishing the current scroll."))
                return true
            }
            let attempt = revision
            operation = Task { [weak self, weak controller] in
                guard let self, let controller else { return }
                defer { if revision == attempt { operation = nil } }
                let result = await controller.run(.nextVideo)
                guard !Task.isCancelled, revision == attempt,
                      self.controller === controller, controller.actionsEnabled else { return }
                switch result {
                case .scrollRequested:
                    feedback(localized("Je fais défiler.", "I am scrolling."))
                case .refused(.signInPage), .unsupported("signin"):
                    feedback(localized("Connecte-toi d’abord sur cette page dans MORE.",
                                       "Sign in on this page in MORE first."))
                case .refused(.notTheFeed):
                    feedback(localized("Ouvre d’abord le fil de vidéos dans cette page.",
                                       "Open the video feed on this page first."))
                default:
                    feedback(localized("Je ne peux pas faire défiler cette page pour le moment.",
                                       "I cannot scroll this page right now."))
                }
            }
        }
        return true
    }

    private func localized(_ french: String, _ english: String) -> String {
        AppLanguage.isFrench ? french : english
    }
}

struct JuryDemoBrowserPresenter: ViewModifier {
    @Bindable var store: MorningStore
    func body(content: Content) -> some View {
        content.morningFullScreenCover(isPresented: Binding(get: { store.juryDemoWebURL != nil },
            set: { if !$0 { store.juryDemoBrowser.close() } })) {
            if let url = store.juryDemoWebURL, let site = WebMorningSite(url: url) {
                WebMorningView(site: site, minutes: 1, initialURL: url,
                    retainedController: store.juryDemoBrowser.controller,
                    onClose: { store.juryDemoBrowser.close() })
            }
        }
    }
}
#endif
