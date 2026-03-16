import Foundation
import OSXQuery

@MainActor
enum SelectorAttributeFormatter {
    static func attributeValue(for element: Element, attributeName: String) -> String? {
        switch canonicalName(attributeName) {
        case "role", "axrole":
            return element.role()
        case "subrole", "axsubrole":
            return element.subrole()
        case "title", "axtitle":
            return element.title()
        case "description", "axdescription":
            return element.descriptionText()
        case "identifier", "axidentifier":
            return element.identifier()
        case "help", "axhelp":
            return element.help()
        case "value", "axvalue":
            return stringify(element.value())
        case "enabled", "axenabled":
            return stringify(element.isEnabled())
        case "focused", "axfocused":
            return stringify(element.isFocused())
        default:
            if let stringValue: String = element.attribute(Attribute<String>(attributeName)) {
                return stringValue
            }
            return stringify(element.rawAttributeValue(named: attributeName))
        }
    }

    static func displayName(for element: Element) -> String? {
        element.title() ??
            element.descriptionText() ??
            element.identifier() ??
            stringify(element.value())
    }

    private static func stringify(_ value: Any?) -> String? {
        switch value {
        case nil:
            nil
        case let string as String:
            string
        case let number as NSNumber:
            number.stringValue
        case let bool as Bool:
            bool ? "true" : "false"
        default:
            String(describing: value!)
        }
    }

    private static func canonicalName(_ attributeName: String) -> String {
        attributeName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
    }
}

@MainActor
enum SelectorQueryFormatter {
    static func format(
        appIdentifier: String,
        selector: String,
        traversedCount: Int,
        matchedCount: Int,
        shown: [Element],
        references: [Element: String]) -> String
    {
        var lines = [
            "stats app=\(appIdentifier) selector=\"\(selector)\" traversed=\(traversedCount) matched=\(matchedCount) shown=\(shown.count)"
        ]

        for element in shown {
            let role = element.role() ?? "AXUnknown"
            let ref = references[element] ?? "?????????"
            if let name = SelectorAttributeFormatter.displayName(for: element) {
                lines.append("\(role) ref=\(ref) name=\"\(escape(name))\"")
            } else {
                lines.append("\(role) ref=\(ref)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }
}
