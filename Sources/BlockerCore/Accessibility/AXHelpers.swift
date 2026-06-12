import ApplicationServices
import Foundation

/// Thin, bounded wrappers around the AXUIElement C API.
/// All functions are synchronous and must run on the main thread.
@MainActor
enum AX {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return result == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let raw = attribute(element, name),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        guard let raw = attribute(element, kAXChildrenAttribute) as? [AnyObject] else { return [] }
        return raw.compactMap { item in
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else { return nil }
            return (item as! AXUIElement)
        }
    }

    static func role(_ element: AXUIElement) -> String? {
        string(element, kAXRoleAttribute)
    }

    static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute)
    }

    static func windows(of app: AXUIElement) -> [AXUIElement] {
        guard let raw = attribute(app, kAXWindowsAttribute) as? [AnyObject] else { return [] }
        return raw.compactMap { item in
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else { return nil }
            return (item as! AXUIElement)
        }
    }

    /// Presses an element's AXPress action. Returns true on success.
    @discardableResult
    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }
}

/// Bounded breadth-first extraction of visible text from a window's
/// accessibility tree. Hard caps on node count, depth, and per-node
/// text length keep CPU and memory flat even on enormous pages.
@MainActor
enum WebContentReader {
    struct Content {
        var url: String?
        var headings: [String] = []
        var linkTexts: [String] = []
        var buttonTexts: [String] = []
        var staticTexts: [String] = []
    }

    static let maxNodes = 600
    static let maxDepth = 14
    static let maxTextLength = 200
    static let maxItemsPerCategory = 80

    static func read(window: AXUIElement) -> Content {
        var content = Content()
        content.url = pageURL(window: window)

        // Score only what the page itself shows: text outside the
        // AXWebArea belongs to browser UI (toolbars, the extensions
        // dropdown, bookmark names, omnibox suggestions) and must not
        // trigger detection. Without a web area (browser-internal
        // pages), detection falls back to title/URL-only scoring.
        guard let webArea = findFirst(role: "AXWebArea", under: window, maxNodes: 400) else {
            return content
        }

        var queue: [(AXUIElement, Int)] = [(webArea, 0)]
        var visited = 0

        while !queue.isEmpty, visited < maxNodes {
            let (node, depth) = queue.removeFirst()
            visited += 1
            guard depth < maxDepth else { continue }

            let role = AX.role(node) ?? ""
            switch role {
            case "AXHeading":
                append(text(of: node), to: &content.headings)
            case "AXLink":
                append(text(of: node), to: &content.linkTexts)
            case "AXButton":
                append(text(of: node), to: &content.buttonTexts)
            case "AXStaticText":
                append(text(of: node), to: &content.staticTexts)
            default:
                break
            }

            // Only descend into containers likely to hold web content;
            // skipping leaf text nodes keeps the walk cheap.
            if role != "AXStaticText" {
                for child in AX.children(node) {
                    queue.append((child, depth + 1))
                }
            }
        }
        return content
    }

    /// Best-effort page URL: AXDocument on the window (Safari, Chrome),
    /// then AXURL on the first AXWebArea found.
    static func pageURL(window: AXUIElement) -> String? {
        if let doc = AX.string(window, kAXDocumentAttribute), !doc.isEmpty {
            return doc
        }
        if let webArea = findFirst(role: "AXWebArea", under: window, maxNodes: 200) {
            if let raw = AX.attribute(webArea, kAXURLAttribute) {
                if let url = raw as? URL { return url.absoluteString }
                if let str = raw as? String { return str }
            }
        }
        // Chrome's internal pages expose no AXDocument or AXURL, but the
        // omnibox shows their full URL with scheme. Only the extension
        // manager is recognised this way — anything else from the address
        // bar is ignored so real pages behave exactly as before. The page
        // can contain its own text fields (e.g. a search box), so every
        // field is checked, not just the first.
        var queue: [AXUIElement] = [window]
        var visited = 0
        while !queue.isEmpty, visited < 300 {
            let node = queue.removeFirst()
            visited += 1
            if AX.role(node) == "AXTextField",
               let value = AX.string(node, kAXValueAttribute),
               value.lowercased().hasPrefix("chrome://extensions") {
                return value
            }
            queue.append(contentsOf: AX.children(node))
        }
        return nil
    }

    static func findFirst(role target: String, under root: AXUIElement, maxNodes: Int) -> AXUIElement? {
        var queue: [AXUIElement] = [root]
        var visited = 0
        while !queue.isEmpty, visited < maxNodes {
            let node = queue.removeFirst()
            visited += 1
            if AX.role(node) == target { return node }
            queue.append(contentsOf: AX.children(node))
        }
        return nil
    }

    private static func text(of element: AXUIElement) -> String? {
        let candidates = [
            AX.string(element, kAXValueAttribute),
            AX.string(element, kAXTitleAttribute),
            AX.string(element, kAXDescriptionAttribute),
        ]
        guard let text = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            return nil
        }
        return String(text.prefix(maxTextLength))
    }

    private static func append(_ text: String?, to list: inout [String]) {
        guard let text, !text.isEmpty, list.count < maxItemsPerCategory else { return }
        list.append(text)
    }
}
