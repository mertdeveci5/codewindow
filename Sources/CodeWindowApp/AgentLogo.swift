import AppKit
import CodeWindowCore
import SwiftUI

struct AgentLogo: View {
    let agent: AgentKind

    var body: some View {
        Group {
            if let logo = AgentLogoAssets.image(for: agent) {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(agent.logoPadding)
            } else {
                Image(systemName: agent.fallbackSymbolName)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(agent.fallbackTint)
            }
        }
        .frame(width: PanelMetrics.glyphSize, height: PanelMetrics.glyphSize)
        .accessibilityHidden(true)
    }
}

@MainActor
enum AgentLogoAssets {
    static func image(for agent: AgentKind) -> NSImage? {
        switch agent {
        case .codex: codex
        case .claude: claude
        case .pi: pi
        }
    }

    static var allAvailable: Bool {
        AgentKind.allCases.allSatisfy { image(for: $0) != nil }
    }

    private static let codex = load(name: "codex", fileExtension: "svg")
    private static let claude = load(name: "claude", fileExtension: "svg")
    private static let pi = load(name: "pi", fileExtension: "svg")

    private static func load(name: String, fileExtension: String) -> NSImage? {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "AgentLogos"
        ) else { return nil }
        return NSImage(contentsOf: url)
    }
}

private extension AgentKind {
    var logoPadding: CGFloat {
        switch self {
        case .codex: 3
        case .pi: 0
        case .claude: 4
        }
    }

    var fallbackSymbolName: String {
        switch self {
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .claude: "sparkles"
        case .pi: "function"
        }
    }

    var fallbackTint: Color {
        switch self {
        case .codex: Color(nsColor: .systemTeal)
        case .claude: Color(nsColor: .systemOrange)
        case .pi: Color(nsColor: .systemIndigo)
        }
    }
}
