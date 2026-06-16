import AppKit
import Foundation

@MainActor
enum LocalAIRemediationActions {
    static let installURL = URL(string: "https://ollama.com/download")!
    static let startCommand = "ollama serve"

    static func pullCommand(modelName: String) -> String {
        let normalized = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return "ollama pull \(normalized.isEmpty ? "llama3.2" : normalized)"
    }

    static func openInstallPage() {
        NSWorkspace.shared.open(installURL)
    }

    static func copyStartCommand() {
        copy(startCommand)
    }

    static func copyPullCommand(modelName: String) {
        copy(pullCommand(modelName: modelName))
    }

    private static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
