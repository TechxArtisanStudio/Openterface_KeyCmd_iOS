import Foundation

/// One row in the Agent chat transcript.
struct AgentMessage: Identifiable {
    enum MessageType {
        case user, assistant, plan, actBar, executionCli, executionMacro
    }

    let id = UUID()
    let type: MessageType
    let text: String?
    let planSteps: [AgentPlanStep]
    let terminalCommand: String?
    let terminalOutputLines: [String]
    let terminalStatus: String?
    let macroSteps: [String]
    let macroProgress: Int
    let macroCurrentStep: Int
    let macroStatusChip: String?
    let isError: Bool

    static func user(_ text: String) -> AgentMessage {
        AgentMessage(type: .user, text: text, planSteps: [], terminalCommand: nil, terminalOutputLines: [], terminalStatus: nil, macroSteps: [], macroProgress: 0, macroCurrentStep: 0, macroStatusChip: nil, isError: false)
    }

    static func assistant(_ text: String) -> AgentMessage {
        AgentMessage(type: .assistant, text: text, planSteps: [], terminalCommand: nil, terminalOutputLines: [], terminalStatus: nil, macroSteps: [], macroProgress: 0, macroCurrentStep: 0, macroStatusChip: nil, isError: false)
    }

    static func assistantError(_ text: String) -> AgentMessage {
        AgentMessage(type: .assistant, text: text, planSteps: [], terminalCommand: nil, terminalOutputLines: [], terminalStatus: nil, macroSteps: [], macroProgress: 0, macroCurrentStep: 0, macroStatusChip: nil, isError: true)
    }

    static func plan(_ steps: [AgentPlanStep]) -> AgentMessage {
        AgentMessage(type: .plan, text: nil, planSteps: steps, terminalCommand: nil, terminalOutputLines: [], terminalStatus: nil, macroSteps: [], macroProgress: 0, macroCurrentStep: 0, macroStatusChip: nil, isError: false)
    }

    static func actBar() -> AgentMessage {
        AgentMessage(type: .actBar, text: nil, planSteps: [], terminalCommand: nil, terminalOutputLines: [], terminalStatus: nil, macroSteps: [], macroProgress: 0, macroCurrentStep: 0, macroStatusChip: nil, isError: false)
    }

    static func executionCli(command: String, outputLines: [String], status: String) -> AgentMessage {
        AgentMessage(type: .executionCli, text: nil, planSteps: [], terminalCommand: command, terminalOutputLines: outputLines, terminalStatus: status, macroSteps: [], macroProgress: 0, macroCurrentStep: 0, macroStatusChip: nil, isError: false)
    }

    static func executionMacro(steps: [String], progress: Int, currentStep: Int, statusChip: String?) -> AgentMessage {
        AgentMessage(type: .executionMacro, text: nil, planSteps: [], terminalCommand: nil, terminalOutputLines: [], terminalStatus: nil, macroSteps: steps, macroProgress: progress, macroCurrentStep: currentStep, macroStatusChip: statusChip, isError: false)
    }
}
