import AppKit
import CodeWindowCore
import SwiftUI

struct SetupNotice: Equatable {
    let id = UUID()
    let message: String
    let succeeded: Bool
}

/// An always-on-top Live Activity: every running session remains visible and
/// each equal-height row shows only its single latest safe action.
/// No timers, no clocks, no repeating animation. The panel only moves when state moves.
struct PanelContentView: View {
    @ObservedObject var store: SessionStore
    let reportHeight: (CGFloat) -> Void
    let installHooks: () -> SetupNotice

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var setupNotice: SetupNotice?

    var body: some View {
        stack
            .padding(PanelMetrics.bezel)
            .frame(width: PanelMetrics.width)
            .background(PanelPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.outerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PanelMetrics.outerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.75)
                    .accessibilityHidden(true)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
                }
            }
            .onPreferenceChange(PanelHeightKey.self, perform: reportHeight)
            .contextMenu {
                Button("Install or update agent hooks…", action: showInstallResult)
                Divider()
                Button("Quit CodeWindow") { NSApplication.shared.terminate(nil) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("CodeWindow, agent activity")
    }

    private var stack: some View {
        VStack(spacing: 0) {
            if let setupNotice {
                SetupNoticeRow(notice: setupNotice)
                    .transition(.opacity)
            }
            if store.sessions.isEmpty {
                EmptyRow()
                    .transition(.opacity)
            } else {
                ForEach(Array(store.sessions.enumerated()), id: \.element.id) { index, session in
                    SessionRow(
                        session: session,
                        showsDivider: index > 0,
                        reduceMotion: reduceMotion
                    )
                    .transition(rowTransition)
                }
            }
        }
        .animation(motion, value: store.sessions.map(\.id))
        .animation(motion, value: setupNotice)
    }

    private func showInstallResult() {
        let notice = installHooks()
        setupNotice = notice
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(6)) {
            if setupNotice?.id == notice.id {
                setupNotice = nil
            }
        }
    }

    private var motion: Animation? {
        guard !reduceMotion else { return nil }
        return .spring(response: 0.30, dampingFraction: 0.88)
    }

    private var rowTransition: AnyTransition {
        .opacity
    }
}

// MARK: - Rows

private struct SetupNoticeRow: View {
    let notice: SetupNotice

    var body: some View {
        HStack(spacing: PanelMetrics.glyphGap) {
            Image(systemName: notice.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(notice.succeeded ? PanelPalette.working : PanelPalette.attention)
                .frame(width: PanelMetrics.glyphSize, height: PanelMetrics.glyphSize)

            Text(notice.message)
                .font(.system(size: PanelMetrics.metaSize, weight: .regular))
                .foregroundStyle(PanelPalette.title)
                .lineLimit(1)

            Spacer(minLength: 6)
        }
        .padding(.horizontal, PanelMetrics.rowInsetHorizontal)
        .frame(height: PanelMetrics.rowHeight)
        .overlay(alignment: .bottom) {
            PanelPalette.divider
                .frame(height: PanelMetrics.separatorHeight)
                .padding(.leading, PanelMetrics.separatorInset)
                .padding(.trailing, PanelMetrics.rowInsetHorizontal)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.message)
    }
}

private struct SessionRow: View {
    let session: PresentedSession
    let showsDivider: Bool
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: PanelMetrics.glyphGap) {
            AgentLogo(agent: session.agent)

            VStack(alignment: .leading, spacing: PanelMetrics.textLineGap) {
                PreviewLine(session: session, reduceMotion: reduceMotion)
                identityLine
            }

            Spacer(minLength: 6)
            StatusMark(session: session, reduceMotion: reduceMotion)
        }
        .padding(.horizontal, PanelMetrics.rowInsetHorizontal)
        .frame(height: PanelMetrics.rowHeight)
        .background {
            if session.needsAttention {
                RoundedRectangle(cornerRadius: PanelMetrics.rowRadius, style: .continuous)
                    .fill(PanelPalette.attention.opacity(0.16))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(PanelPalette.attention)
                            .frame(
                                width: PanelMetrics.attentionRailWidth,
                                height: PanelMetrics.attentionRailHeight
                            )
                            .padding(.leading, 2)
                    }
            }
        }
        .overlay(alignment: .top) {
            if showsDivider {
                PanelPalette.divider
                    .frame(height: PanelMetrics.separatorHeight)
                    .padding(.leading, PanelMetrics.separatorInset)
                    .padding(.trailing, PanelMetrics.rowInsetHorizontal)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.accessibilityDescription)
    }

    /// Identity is supporting metadata; the changing live action remains dominant.
    private var identityLine: some View {
        HStack(spacing: 4) {
            Text(session.metadataLabel)
                .fixedSize()
            Text("·")
            Text(session.projectLabel)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1)
        }
        .font(.system(size: PanelMetrics.metaSize, weight: .regular))
        .foregroundStyle(PanelPalette.meta)
    }
}

/// The latest safe subject. Cross-fades in place when the text changes so the row never jumps.
private struct PreviewLine: View {
    let session: PresentedSession
    let reduceMotion: Bool

    var body: some View {
        Text(session.primaryLabel)
            .font(primaryFont)
            .foregroundStyle(primaryColor)
            .lineLimit(1)
            .truncationMode(session.prefersLeadingTruncation ? .head : .tail)
            .transition(transition)
            .id(session.primaryLabel)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: session.primaryLabel)
    }

    private var primaryFont: Font {
        if session.usesMonospacedPreview {
            return .system(size: PanelMetrics.commandSize, weight: .regular, design: .monospaced)
        }
        return .system(size: PanelMetrics.actionSize, weight: .regular)
    }

    private var primaryColor: Color {
        if session.needsAttention { return PanelPalette.attention }
        if session.isDiagnostic { return PanelPalette.diagnostic }
        return PanelPalette.title
    }

    private var transition: AnyTransition {
        .opacity
    }
}

private struct StatusMark: View {
    let session: PresentedSession
    let reduceMotion: Bool

    var body: some View {
        Group {
            if session.needsAttention {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: PanelMetrics.statusDot, height: PanelMetrics.statusDot)
            }
        }
        .frame(width: PanelMetrics.statusColumn)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: session.activity)
        .accessibilityHidden(true)
    }

    private var tint: Color {
        if session.isDiagnostic { return PanelPalette.attention.opacity(0.55) }
        switch session.activity {
        case .needsAttention: return PanelPalette.attention
        case .working: return PanelPalette.working
        case .starting: return PanelPalette.starting
        case .idle, .ended: return PanelPalette.muted
        }
    }
}

private struct EmptyRow: View {
    var body: some View {
        HStack(spacing: PanelMetrics.glyphGap) {
            Circle()
                .fill(PanelPalette.muted)
                .frame(width: PanelMetrics.statusDot, height: PanelMetrics.statusDot)
                .frame(width: PanelMetrics.glyphSize, height: PanelMetrics.glyphSize)

            VStack(alignment: .leading, spacing: PanelMetrics.textLineGap) {
                Text("No agents running")
                    .font(.system(size: PanelMetrics.actionSize, weight: .regular))
                    .foregroundStyle(PanelPalette.title)
                Text("watching codex · claude · pi")
                    .font(.system(size: PanelMetrics.metaSize, weight: .regular))
                    .foregroundStyle(PanelPalette.meta)
            }

            Spacer(minLength: 6)
        }
        .padding(.horizontal, PanelMetrics.rowInsetHorizontal)
        .frame(height: PanelMetrics.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CodeWindow, no terminal agents")
    }
}

private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum PanelPalette {
    static let surface = Color(red: 0.025, green: 0.025, blue: 0.029)
    static let title = Color.white.opacity(0.96)
    static let meta = Color.white.opacity(0.48)
    static let diagnostic = Color.white.opacity(0.64)
    static let attention = Color(nsColor: .systemOrange)
    static let working = Color(nsColor: .systemGreen)
    static let starting = Color(nsColor: .systemBlue)
    static let muted = Color.white.opacity(0.30)
    static let divider = Color.white.opacity(0.075)
}
