import CodeWindowCore
import SwiftUI

struct InspectorContentView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var model: InspectorModel
    let hoverChanged: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let session = model.session {
                content(for: session)
            } else {
                Color.clear
            }
        }
        .frame(width: PanelMetrics.width, height: PanelMetrics.inspectorHeight)
        .background(PanelPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.outerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PanelMetrics.outerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.75)
                .accessibilityHidden(true)
        }
        .onHover(perform: hoverChanged)
    }

    private func content(for session: PresentedSession) -> some View {
        VStack(spacing: 0) {
            header(for: session)

            // The panel row is one line by design, so the inspector is where its text has to be
            // readable in full — including before any feed events have arrived.
            if session.hasPreview {
                Text(session.primaryLabel)
                    .font(.system(size: PanelMetrics.actionSize, weight: .regular))
                    .foregroundStyle(PanelPalette.title)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, PanelMetrics.rowInsetHorizontal)
                    .padding(.bottom, 10)
            }

            PanelPalette.divider
                .frame(height: PanelMetrics.separatorHeight)
                .padding(.horizontal, PanelMetrics.rowInsetHorizontal)

            feed(for: session)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live activity for \(session.agent.displayName) in \(session.projectLabel)")
    }

    private func header(for session: PresentedSession) -> some View {
        HStack(spacing: PanelMetrics.glyphGap) {
            AgentLogo(agent: session.agent)

            VStack(alignment: .leading, spacing: PanelMetrics.textLineGap) {
                Text(session.projectLabel)
                    .font(.system(size: PanelMetrics.actionSize, weight: .medium))
                    .foregroundStyle(PanelPalette.title)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(session.agent.displayName.lowercased()) · \(session.statusDescription)")
                    .font(.system(size: PanelMetrics.metaSize, weight: .regular))
                    .foregroundStyle(PanelPalette.meta)
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Circle()
                    .fill(PanelPalette.statusColor(for: session))
                    .frame(width: PanelMetrics.statusDot, height: PanelMetrics.statusDot)
                Text("LIVE")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(PanelPalette.meta)
            }
        }
        .padding(.horizontal, PanelMetrics.rowInsetHorizontal)
        .frame(height: 48)
    }

    @ViewBuilder
    private func feed(for session: PresentedSession) -> some View {
        let events = store.feeds[session.id] ?? []
        if events.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: session.isDiagnostic ? "wrench.and.screwdriver" : "ellipsis.message")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(PanelPalette.muted)
                Text(session.isDiagnostic ? "Install hooks to see live activity" : "Waiting for the next update")
                    .font(.system(size: PanelMetrics.actionSize, weight: .regular))
                    .foregroundStyle(PanelPalette.meta)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 13) {
                        ForEach(events) { event in
                            FeedEventRow(event: event)
                                .id(event.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                }
                .scrollIndicators(.hidden)
                .onAppear { scrollToLatest(events, using: proxy, animated: false) }
                .onChange(of: events.last?.id) { _ in
                    scrollToLatest(events, using: proxy, animated: !reduceMotion)
                }
            }
        }
    }

    private func scrollToLatest(
        _ events: [SessionFeedEvent],
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        guard let latest = events.last else { return }
        let scroll = { proxy.scrollTo(latest.id, anchor: .bottom) }
        if animated {
            withAnimation(.easeOut(duration: 0.18), scroll)
        } else {
            scroll()
        }
    }
}

private struct FeedEventRow: View {
    let event: SessionFeedEvent

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbolName)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 13, height: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(tint.opacity(0.92))

                Text(event.text)
                    .font(textFont)
                    .foregroundStyle(PanelPalette.title.opacity(0.90))
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = event.detail {
                    // The inspector is where the whole command belongs. Clipping it here leaves
                    // the text nowhere to be read, since the panel row is a single line.
                    Text(detail)
                        .font(detailFont)
                        .foregroundStyle(PanelPalette.meta)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch event.kind {
        case .user: "YOU"
        case .assistant: "ASSISTANT"
        case .toolCall: "TOOL"
        case .toolResult: event.succeeded == false ? "FAILED" : "DONE"
        case .attention: "ATTENTION"
        }
    }

    private var symbolName: String {
        switch event.kind {
        case .user: "person.fill"
        case .assistant: "sparkles"
        case .toolCall: "hammer.fill"
        case .toolResult: event.succeeded == false ? "xmark.circle.fill" : "checkmark.circle.fill"
        case .attention: "exclamationmark.circle.fill"
        }
    }

    private var tint: Color {
        switch event.kind {
        case .attention: PanelPalette.attention
        case .toolResult where event.succeeded == false: PanelPalette.attention
        case .toolResult: PanelPalette.working
        case .user: PanelPalette.starting
        case .assistant, .toolCall: PanelPalette.meta
        }
    }

    private var textFont: Font {
        event.kind == .toolCall
            ? .system(size: PanelMetrics.commandSize, weight: .regular, design: .monospaced)
            : .system(size: PanelMetrics.actionSize, weight: .regular)
    }

    private var detailFont: Font {
        event.kind == .toolCall
            ? .system(size: PanelMetrics.metaSize, weight: .regular, design: .monospaced)
            : .system(size: PanelMetrics.metaSize, weight: .regular)
    }
}
