import Foundation

/// One row in the Agent chat transcript (marketing demo).
struct AgentMessage: Identifiable {
    enum MessageType {
        case user, assistant, plan, actBar, executionCli, executionMacro
    }

    let id = UUID()
    let type: MessageType
    let text: String?
    let planSteps: [AgentPlanStep]
    let terminalLines: [String]
    let macroSteps: [String]
    let macroProgress: Int
    let macroCurrentStep: Int
    let macroStatusChip: String?

    static func user(_ text: String) -> AgentMessage {
        AgentMessage(type: .user, text: text, planSteps: [], terminalLines: [], macroSteps: [], macroProgress: 0, macroCurrentStep: 0, macroStatusChip: nil)
    }

    static func assistant(_ text: String) -> AgentMessage {
        AgentMessage(type: .assistant, text: text, planSteps: [], terminalLines: [], macroSteps: [], macroProgress: 0, macroCurrentStep: 0, macroStatusChip: nil)
    }

    static func plan(_ steps: [AgentPlanStep]) -> AgentMessage {
        AgentMessage(type: .plan, text: nil, planSteps: steps, terminalLines: [], macroSteps: [], macroProgress: 0, macroCurrentStep: 0, macroStatusChip: nil)
    }

    static func actBar() -> AgentMessage {
        AgentMessage(type: .actBar, text: nil, planSteps: [], terminalLines: [], macroSteps: [], macroProgress: 0, macroCurrentStep: 0, macroStatusChip: nil)
    }

    static func executionCli(_ lines: [String]) -> AgentMessage {
        AgentMessage(type: .executionCli, text: nil, planSteps: [], terminalLines: lines, macroSteps: [], macroProgress: 0, macroCurrentStep: 0, macroStatusChip: nil)
    }

    static func executionMacro(steps: [String], progress: Int, currentStep: Int, statusChip: String?) -> AgentMessage {
        AgentMessage(type: .executionMacro, text: nil, planSteps: [], terminalLines: [], macroSteps: steps, macroProgress: progress, macroCurrentStep: currentStep, macroStatusChip: statusChip)
    }
}
