import Foundation
import ApplicationServices

public final class TeamsAccessibilityTextCollector {
    private let maxNodes: Int
    private let textAttributes = [
        kAXTitleAttribute,
        "AXLabel",
        kAXDescriptionAttribute,
        kAXValueAttribute
    ]

    public init(maxNodes: Int = 1000) {
        self.maxNodes = maxNodes
    }

    public func collectTexts(for processID: pid_t) -> [String] {
        let appElement = AXUIElementCreateApplication(processID)
        var queue: [AXUIElement] = [appElement]
        var index = 0
        var visited = 0
        var texts: [String] = []

        while index < queue.count, visited < maxNodes {
            let element = queue[index]
            index += 1
            visited += 1

            for attr in textAttributes {
                if let text = stringAttribute(attr, from: element), !text.isEmpty {
                    texts.append(text)
                }
            }

            if let children = elementArrayAttribute(kAXChildrenAttribute, from: element), !children.isEmpty {
                queue.append(contentsOf: children)
            }
        }

        return texts
    }

    private func stringAttribute(_ attr: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
        guard result == .success, let value else { return nil }

        if CFGetTypeID(value) == CFStringGetTypeID() {
            return value as? String
        }
        if CFGetTypeID(value) == CFAttributedStringGetTypeID() {
            return (value as? NSAttributedString)?.string
        }
        return nil
    }

    private func elementArrayAttribute(_ attr: String, from element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
        guard result == .success, let value else { return nil }
        return value as? [AXUIElement]
    }
}
