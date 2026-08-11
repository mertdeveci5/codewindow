import AppKit
import CodeWindowCore
import SwiftUI

struct AgentLogo: View {
    let agent: AgentKind

    var body: some View {
        RoundedRectangle(cornerRadius: PanelMetrics.glyphRadius, style: .continuous)
            .fill(agent.logoBackground.opacity(agent.logoBackgroundOpacity))
            .frame(width: PanelMetrics.glyphSize, height: PanelMetrics.glyphSize)
            .overlay {
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
            .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.glyphRadius, style: .continuous))
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

    private static let codex = load(name: "codex", fileExtension: "png")
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
    var logoBackground: Color {
        switch self {
        case .codex, .pi: .black
        case .claude: Color(red: 0.94, green: 0.92, blue: 0.87)
        }
    }

    var logoPadding: CGFloat {
        switch self {
        case .codex, .pi: 0
        case .claude: 4
        }
    }

    var logoBackgroundOpacity: Double {
        switch self {
        case .codex, .pi: 1
        case .claude: 0.82
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
