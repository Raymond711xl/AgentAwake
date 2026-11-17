import Foundation

public enum ChatGPTChatControls {
    private static let editorLabels: Set<String> = [
        "ask chatgpt", "询问 chatgpt", "問問 chatgpt", "問 chatgpt"
    ]
    private static let stopLabels: Set<String> = [
        "stop", "stop generating", "停止", "停止生成"
    ]

    public static func isChatEditor(labels: [String]) -> Bool {
        labels.contains { editorLabels.contains(normalized($0)) }
    }

    public static func isPrimaryComposerButton(classes: [String]) -> Bool {
        classes.contains("size-token-button-composer")
            && classes.contains("bg-composer-primary")
    }

    public static func isStopButton(labels: [String], classes: [String]) -> Bool {
        isPrimaryComposerButton(classes: classes)
            && labels.contains { stopLabels.contains(normalized($0)) }
    }

    private static func normalized(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
