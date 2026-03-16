import AppKit
import Foundation
import OSXQuery

@MainActor
final class PenguinQueryService {
    struct QuerySnapshot {
        let appPID: pid_t
        let maxDepth: Int
        let root: Element
        let childrenByElement: [Element: [Element]]
        let parentByElement: [Element: Element]
        let roleByElement: [Element: String]
        let frameByElement: [Element: CGRect]
    }

    let refStore = SelectorActionRefStore()
    private var snapshot: QuerySnapshot?

    func execute(_ request: PenguinQueryRequest) throws -> String {
        let root = try Self.resolveRootElement(appIdentifier: request.appIdentifier)
        let appPID = root.pid() ?? 0
        let snapshot = try self.resolveSnapshot(
            root: root,
            appPID: appPID,
            request: request)

        let selectorEngine = OXQSelectorEngine<Element>(
            children: { snapshot.childrenByElement[$0] ?? [] },
            role: { snapshot.roleByElement[$0] ?? $0.role() },
            attributeValue: { element, attributeName in
                SelectorAttributeFormatter.attributeValue(for: element, attributeName: attributeName)
            })

        let memoizationContext = OXQQueryMemoizationContext<Element>(
            childrenProvider: { snapshot.childrenByElement[$0] ?? [] },
            roleProvider: { snapshot.roleByElement[$0] ?? $0.role() },
            attributeValueProvider: { element, attributeName in
                SelectorAttributeFormatter.attributeValue(for: element, attributeName: attributeName)
            },
            preferDerivedComputedName: true)

        let evaluation = try selectorEngine.findAllWithMetrics(
            matching: request.selector,
            from: snapshot.root,
            maxDepth: request.maxDepth,
            memoizationContext: memoizationContext)

        let shown = Array(evaluation.matches.prefix(request.limit == 0 ? Int.max : request.limit))
        let referenceMap = Self.references(for: shown)
        let storedReferences = shown.map { element in
            let reference = referenceMap[element]!
            let parentReference = snapshot.parentByElement[element].flatMap { referenceMap[$0] }
            return SelectorActionRefStore.StoredReference(
                reference: reference,
                element: element,
                frame: snapshot.frameByElement[element] ?? element.frame(),
                parentReference: parentReference,
                role: snapshot.roleByElement[element] ?? element.role())
        }
        self.refStore.replace(with: storedReferences, appPID: appPID > 0 ? appPID : nil)

        return SelectorQueryFormatter.format(
            appIdentifier: request.appIdentifier,
            selector: request.selector,
            traversedCount: evaluation.traversedNodeCount,
            matchedCount: evaluation.matches.count,
            shown: shown,
            references: referenceMap)
    }

    private func resolveSnapshot(
        root: Element,
        appPID: pid_t,
        request: PenguinQueryRequest) throws -> QuerySnapshot
    {
        if request.useCachedSnapshot {
            guard let snapshot else {
                throw QueryServiceError("No cached snapshot available. Run a cached query first.")
            }
            guard snapshot.appPID == appPID else {
                throw QueryServiceError("Cached snapshot belongs to another app. Refresh the query.")
            }
            guard snapshot.maxDepth >= request.maxDepth else {
                throw QueryServiceError("Cached snapshot depth is shallower than requested depth.")
            }
            return snapshot
        }

        let snapshot = Self.captureSnapshot(root: root, maxDepth: request.maxDepth)
        if request.cacheSessionEnabled || true {
            self.snapshot = snapshot
        }
        return snapshot
    }

    private static func captureSnapshot(root: Element, maxDepth: Int) -> QuerySnapshot {
        var childrenByElement: [Element: [Element]] = [:]
        var parentByElement: [Element: Element] = [:]
        var roleByElement: [Element: String] = [:]
        var frameByElement: [Element: CGRect] = [:]
        var visited: Set<Element> = []
        var queue: [(Element, Int)] = [(root, 0)]

        while !queue.isEmpty {
            let (element, depth) = queue.removeFirst()
            guard visited.insert(element).inserted else { continue }

            roleByElement[element] = element.role() ?? "AXUnknown"
            frameByElement[element] = element.frame()

            let children = depth < maxDepth ? (element.children() ?? []) : []
            childrenByElement[element] = children

            for child in children {
                if parentByElement[child] == nil {
                    parentByElement[child] = element
                }
                queue.append((child, depth + 1))
            }
        }

        return QuerySnapshot(
            appPID: root.pid() ?? 0,
            maxDepth: maxDepth,
            root: root,
            childrenByElement: childrenByElement,
            parentByElement: parentByElement,
            roleByElement: roleByElement,
            frameByElement: frameByElement)
    }

    private static func resolveRootElement(appIdentifier: String) throws -> Element {
        let trimmed = appIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("focused") == .orderedSame {
            if let element = Element.focusedApplication() {
                return element
            }
            throw QueryServiceError("Could not resolve the focused application.")
        }

        if let pid = pid_t(trimmed), let element = getApplicationElement(for: pid) {
            return element
        }

        if let element = getApplicationElement(for: trimmed) {
            return element
        }

        if let app = RunningApplicationHelper.allApplications().first(where: {
            ($0.bundleIdentifier?.caseInsensitiveCompare(trimmed) == .orderedSame) ||
                ($0.localizedName?.caseInsensitiveCompare(trimmed) == .orderedSame)
        }) {
            return Element(AXUIElement.application(pid: app.processIdentifier))
        }

        throw QueryServiceError("Could not find running app '\(appIdentifier)'.")
    }

    private static func references(for elements: [Element]) -> [Element: String] {
        var seen: Set<String> = []
        var mapping: [Element: String] = [:]

        for (index, element) in elements.enumerated() {
            var candidate = String(format: "%09x", CFHash(element.underlyingElement) & 0x1fffffff)
            if seen.contains(candidate) {
                candidate = String(format: "%09x", index)
            }
            seen.insert(candidate)
            mapping[element] = candidate
        }

        return mapping
    }
}

private struct QueryServiceError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { self.message }
}
