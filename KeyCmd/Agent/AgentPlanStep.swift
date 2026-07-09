import Foundation

/// One step in an Agent plan card (marketing demo).
struct AgentPlanStep: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case terminal, macro, hid
    }

    let id = UUID()
    let index: Int
    let title: String
    let subtitle: String?
    let kind: Kind
}
