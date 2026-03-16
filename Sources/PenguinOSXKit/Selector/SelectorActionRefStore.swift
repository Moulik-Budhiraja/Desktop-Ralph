import Foundation
import OSXQuery

@MainActor
final class SelectorActionRefStore {
    struct StoredReference {
        let reference: String
        let element: Element
        let frame: CGRect?
        let parentReference: String?
        let role: String?
    }

    private(set) var snapshotAppPID: pid_t?
    private(set) var hasSnapshot = false
    private var referencesByID: [String: StoredReference] = [:]

    func replace(with references: [StoredReference], appPID: pid_t?) {
        self.referencesByID = Dictionary(uniqueKeysWithValues: references.map { ($0.reference.lowercased(), $0) })
        self.snapshotAppPID = appPID
        self.hasSnapshot = true
    }

    func clear() {
        self.referencesByID = [:]
        self.snapshotAppPID = nil
        self.hasSnapshot = false
    }

    func element(for reference: String) -> Element? {
        self.referencesByID[reference.lowercased()]?.element
    }

    func frame(for reference: String) -> CGRect? {
        self.referencesByID[reference.lowercased()]?.frame
    }

    func parentReference(for reference: String) -> String? {
        self.referencesByID[reference.lowercased()]?.parentReference
    }

    func role(for reference: String) -> String? {
        self.referencesByID[reference.lowercased()]?.role
    }
}
