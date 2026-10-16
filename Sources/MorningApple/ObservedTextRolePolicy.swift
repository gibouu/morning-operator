import Foundation

/// Narrow negative roles shared by header and visible-task grounding. This does
/// not identify apps, infer actions, remove source text, or judge written reports.
enum ObservedTextRolePolicy {
    static func isProvenanceLine(_ line: String) -> Bool {
        let folded = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let tokens = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let markers: Set<String> = ["synthetic", "synthetique", "simulated", "simulation", "demo", "demonstration",
            "test", "testing", "recording", "recorded", "capture", "captured", "enregistrement", "provenance", "watermark", "filigrane"]
        let qualifiers: Set<String> = ["metadata", "metadonnees", "screen", "video", "version", "fr", "en",
            "francais", "francaise", "french", "english", "anglais", "on", "le", "de", "the"]
        if tokens.contains(where: markers.contains), tokens.allSatisfy({
            markers.contains($0) || qualifiers.contains($0) || $0.allSatisfy(\.isNumber)
        }) { return true }

        // An explicit negative inventory of real effects is a disclaimer, not
        // evidence that those effects occurred. Extra task words preserve a line.
        let disclaimer: Set<String> = ["no", "real", "account", "accounts", "send", "sending", "sent", "sends",
            "write", "writes", "writing", "like", "likes", "or", "and", "external", "effect", "effects",
            "aucun", "aucune", "reel", "reelle", "compte", "comptes", "envoi", "envois", "ecriture", "ecritures",
            "aime", "j", "ni", "ou", "et", "externe"]
        let roles: [Set<String>] = [["account", "accounts", "compte", "comptes"],
            ["send", "sending", "sent", "sends", "envoi", "envois"],
            ["write", "writes", "writing", "ecriture", "ecritures"], ["like", "likes", "aime"]]
        return (4...20).contains(tokens.count) && ["no", "aucun", "aucune"].contains(tokens.first ?? "") &&
            tokens.contains(where: { ["real", "reel", "reelle"].contains($0) }) &&
            tokens.allSatisfy(disclaimer.contains) && roles.filter { !Set(tokens).isDisjoint(with: $0) }.count >= 3
    }
}
