import AgentAwakeCore
import ApplicationServices
import Foundation

final class ChatGPTChatDetector: @unchecked Sendable {
    static let bundleIdentifier = "com.openai.codex"

    enum State: Equatable, Sendable {
        case permissionRequired
        case noComposer
        case idle
        case generating
    }

    private struct Composer {
        let window: AXUIElement
        let editor: AXUIElement
        let container: AXUIElement
    }

    private struct SearchBudget {
        private var nodesRemaining = 200
        private let deadline = ProcessInfo.processInfo.systemUptime + 0.60

        mutating func visit() -> Bool {
            guard nodesRemaining > 0,
                  ProcessInfo.processInfo.systemUptime < deadline
            else { return false }
            nodesRemaining -= 1
            return true
        }
    }

    private static let webArea = "AXWebArea"
    private static let domClassList = "AXDOMClassList"
    private static let leaves: Set<String> = [
        "AXButton", "AXStaticText", "AXImage", "AXHeading", "AXLink",
        "AXTextField", "AXTextArea", "AXScrollBar", "AXMenuButton"
    ]

    // The controller performs one sample at a time on a background thread.
    private var composers: [Composer] = []

    func state(for processIDs: [pid_t]) -> State {
        guard AXIsProcessTrusted() else {
            composers.removeAll()
            return .permissionRequired
        }
        guard !processIDs.isEmpty else {
            composers.removeAll()
            return .noComposer
        }

        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.12)
        defer { AXUIElementSetMessagingTimeout(system, 0) }

        var budget = SearchBudget()
        var observedComposers: [Composer] = []
        var sawIdleComposer = false
        var isGenerating = false
        for pid in processIDs.prefix(2) {
            let app = AXUIElementCreateApplication(pid)
            for window in elements(app, kAXWindowsAttribute as CFString, limit: 5) {
                if let known = composers.first(where: { CFEqual($0.window, window) }),
                   isChatEditor(known.editor),
                   let button = primaryAction(in: known.container, budget: &budget)
                {
                    observedComposers.append(known)
                    let state = actionState(button)
                    isGenerating = isGenerating || state == .generating
                    sawIdleComposer = sawIdleComposer || state == .idle
                    continue
                }

                guard let document = search(in: window, budget: &budget, matching: {
                    $1 == Self.webArea && self.isDesktopDocument($0)
                }), let editor = search(in: document, budget: &budget, matching: {
                    self.isChatEditor($0, role: $1)
                }) else { continue }

                // Find the composer action in a shared ancestor below the
                // web area so a Stop button elsewhere cannot match this input.
                var ancestor = editor
                for _ in 0..<7 {
                    guard let parent: AXUIElement = attribute(
                        ancestor, kAXParentAttribute as CFString
                    ), !CFEqual(parent, document), budget.visit() else { break }
                    ancestor = parent
                    if let button = primaryAction(in: ancestor, budget: &budget) {
                        observedComposers.append(.init(
                            window: window, editor: editor, container: ancestor
                        ))
                        let state = actionState(button)
                        isGenerating = isGenerating || state == .generating
                        sawIdleComposer = sawIdleComposer || state == .idle
                        break
                    }
                }
            }
        }
        composers = observedComposers
        if isGenerating { return .generating }
        return sawIdleComposer ? .idle : .noComposer
    }

    private func primaryAction(
        in element: AXUIElement, budget: inout SearchBudget
    ) -> AXUIElement? {
        search(in: element, maxDepth: 6, budget: &budget) { element, role in
            guard role == kAXButtonRole as String else { return false }
            return ChatGPTChatControls.isPrimaryComposerButton(
                classes: self.classes(of: element)
            )
        }
    }

    private func actionState(_ button: AXUIElement) -> State {
        let labels = labels(of: button)
        let classes = classes(of: button)
        guard !labels.isEmpty, ChatGPTChatControls.isPrimaryComposerButton(classes: classes)
        else { return .noComposer }
        return ChatGPTChatControls.isStopButton(labels: labels, classes: classes)
            ? .generating : .idle
    }

    private func isChatEditor(_ element: AXUIElement, role: String? = nil) -> Bool {
        let role = role ?? attribute(element, kAXRoleAttribute as CFString) ?? ""
        guard role == kAXTextAreaRole as String || role == kAXTextFieldRole as String
        else { return false }
        let placeholder: String? = attribute(element, kAXPlaceholderValueAttribute as CFString)
        return ChatGPTChatControls.isChatEditor(
            labels: labels(of: element) + (placeholder.map { [$0] } ?? [])
        )
    }

    private func isDesktopDocument(_ element: AXUIElement) -> Bool {
        let address: CFTypeRef? = attribute(element, kAXURLAttribute as CFString)
        let url = address as? URL ?? (address as? String).flatMap(URL.init(string:))
        guard let url else { return false }
        if url.scheme == "app" { return url.host == "-" || (url.host ?? "").isEmpty }
        return url.isFileURL && url.path.contains("/Contents/Resources/")
            && url.path.hasSuffix("/webview/index.html")
    }

    private func search(
        in root: AXUIElement,
        maxDepth: Int = 16,
        budget: inout SearchBudget,
        matching: (AXUIElement, String) -> Bool
    ) -> AXUIElement? {
        var pending = [(element: root, depth: 0)]
        while let (element, depth) = pending.popLast(), budget.visit() {
            guard let role: String = attribute(element, kAXRoleAttribute as CFString)
            else { continue }
            if matching(element, role) { return element }
            guard depth < maxDepth, !Self.leaves.contains(role),
                  depth == 0 || role != Self.webArea else { continue }
            // The composer is near the end of the document. Skip over large
            // history subtrees and never query an editor's text value.
            pending.append(contentsOf: elements(
                element, kAXChildrenAttribute as CFString, limit: 18, fromEnd: true
            ).map { ($0, depth + 1) })
        }
        return nil
    }

    private func labels(of element: AXUIElement) -> [String] {
        let title: String? = attribute(element, kAXTitleAttribute as CFString)
        let description: String? = attribute(element, kAXDescriptionAttribute as CFString)
        return [title, description].compactMap { $0 }
    }

    private func classes(of element: AXUIElement) -> [String] {
        attribute(element, Self.domClassList as CFString) ?? []
    }

    private func attribute<Value>(_ element: AXUIElement, _ name: CFString) -> Value? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success
        else { return nil }
        return value as? Value
    }

    private func elements(
        _ element: AXUIElement,
        _ name: CFString,
        limit: Int,
        fromEnd: Bool = false
    ) -> [AXUIElement] {
        var count: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(element, name, &count) == .success,
              count > 0 else { return [] }
        let index = fromEnd ? max(0, count - limit) : 0
        var values: CFArray?
        guard AXUIElementCopyAttributeValues(
            element, name, index, min(count, limit), &values
        ) == .success else { return [] }
        return values as? [AXUIElement] ?? []
    }
}
