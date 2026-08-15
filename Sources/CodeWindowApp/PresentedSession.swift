import CodeWindowCore
import Foundation

enum PresentedSession: Equatable, Identifiable, Sendable {
    case reported(SessionState)
    case detected(TerminalAgentProcess)

    var id: String {
        switch self {
        case let .reported(state): state.id
        case let .detected(session):
            "terminal-\(session.process.pid)-\(session.process.startedAtSeconds)-\(session.process.startedAtMicroseconds)"
        }
    }

    var agent: AgentKind {
        switch self {
        case let .reported(state): state.agent
        case let .detected(session): session.agent
        }
    }

    var process: ProcessStamp {
        switch self {
        case let .reported(state): state.process
        case let .detected(session): session.process
        }
    }

    var projectLabel: String {
        switch self {
        case let .reported(state): state.projectLabel
        case let .detected(session): session.projectLabel
        }
    }

    var activity: Activity {
        switch self {
        case let .reported(state): state.activity
        case .detected: .starting
        }
    }

    /// The single most recent action for this session; the panel never shows history.
    var actionLabel: String {
        switch self {
        case let .reported(state): state.action.label
        case .detected: "hooks not reporting"
        }
    }

    /// A safe current subject when hooks provide one; otherwise the generic action remains useful.
    var primaryLabel: String {
        switch self {
        case let .reported(state):
            return state.actionPreview
                ?? ([.thinking, .waiting].contains(state.action) ? state.taskPreview : nil)
                ?? state.action.label
        case .detected:
            return actionLabel
        }
    }

    var hasPreview: Bool {
        primaryLabel != actionLabel
    }

    var metadataLabel: String {
        if isDiagnostic { return "setup needed" }
        return (hasPreview ? actionLabel : agent.displayName).lowercased()
    }

    var usesMonospacedPreview: Bool {
        guard case let .reported(state) = self else { return false }
        return state.action == .runningCommand && state.actionPreview != nil
    }

    var prefersLeadingTruncation: Bool {
        usesMonospacedPreview
    }

    var isDiagnostic: Bool {
        if case .detected = self { true } else { false }
    }

    /// Attention rows get the emphasized treatment: tinted capsule, accent text, alert glyph.
    var needsAttention: Bool {
        activity == .needsAttention
    }

    var statusDescription: String {
        if isDiagnostic { return "hooks not reporting" }
        switch activity {
        case .starting: return "starting"
        case .working: return "working"
        case .needsAttention: return "needs attention"
        case .idle: return "idle"
        case .ended: return "ended"
        }
    }

    var accessibilityDescription: String {
        var parts = [agent.displayName, "project \(projectLabel)", actionLabel]
        if primaryLabel != actionLabel {
            parts.append(primaryLabel)
        }
        if statusDescription != actionLabel {
            parts.append(statusDescription)
        }
        return parts.joined(separator: ", ")
    }

    var updatedAt: Date {
        switch self {
        case let .reported(state): state.updatedAt
        case let .detected(session):
            Date(timeIntervalSince1970: TimeInterval(session.process.startedAtSeconds))
        }
    }
}
