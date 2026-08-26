import SwiftUI

/// Status rows grow with their text. Clipping a setup step or a failure reason to one line
/// hides the very thing the row exists to say.
private struct PanelStatusRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, PanelMetrics.rowInsetHorizontal)
            .padding(.vertical, PanelMetrics.rowInsetVertical)
            .frame(minHeight: PanelMetrics.rowHeight)
            .overlay(alignment: .bottom) {
                PanelPalette.divider
                    .frame(height: PanelMetrics.separatorHeight)
                    .padding(.leading, PanelMetrics.separatorInset)
                    .padding(.trailing, PanelMetrics.rowInsetHorizontal)
            }
    }
}

private extension View {
    func panelStatusRow() -> some View {
        modifier(PanelStatusRow())
    }
}

struct HookSetupRow: View {
    let isInstalling: Bool
    let install: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: PanelMetrics.glyphGap) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(PanelPalette.working)
                .frame(width: PanelMetrics.glyphSize, height: PanelMetrics.glyphSize)

            VStack(alignment: .leading, spacing: PanelMetrics.textLineGap) {
                Text("Connect your agents")
                    .font(.system(size: PanelMetrics.actionSize, weight: .regular))
                    .foregroundStyle(PanelPalette.title)
                Text("Install hooks for live updates")
                    .font(.system(size: PanelMetrics.metaSize, weight: .regular))
                    .foregroundStyle(PanelPalette.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button(action: install) {
                Text(isInstalling ? "Installing…" : "Install")
                    .font(.system(size: PanelMetrics.metaSize, weight: .medium))
                    .foregroundStyle(PanelPalette.title)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                    .contentShape(Capsule())
            }
                .buttonStyle(.plain)
                .disabled(isInstalling)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(PanelPalette.meta)
                    .frame(width: 16, height: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not now")
        }
        .panelStatusRow()
        .accessibilityElement(children: .contain)
    }
}

struct NoticeRow: View {
    let notice: PanelNotice

    var body: some View {
        HStack(spacing: PanelMetrics.glyphGap) {
            Image(systemName: notice.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(notice.succeeded ? PanelPalette.working : PanelPalette.attention)
                .frame(width: PanelMetrics.glyphSize, height: PanelMetrics.glyphSize)

            Text(notice.message)
                .font(.system(size: PanelMetrics.metaSize, weight: .regular))
                .foregroundStyle(PanelPalette.title)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 6)
        }
        .panelStatusRow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.message)
    }
}

struct CloudViewStatusRow: View {
    let status: CloudViewStatusPresentation
    let retry: () -> Void

    var body: some View {
        HStack(spacing: PanelMetrics.glyphGap) {
            Group {
                if status.isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: status.isError ? "icloud.slash" : "icloud")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(status.isError ? PanelPalette.attention : PanelPalette.working)
                }
            }
            .frame(width: PanelMetrics.glyphSize, height: PanelMetrics.glyphSize)

            VStack(alignment: .leading, spacing: PanelMetrics.textLineGap) {
                Text(status.title)
                    .font(.system(size: PanelMetrics.actionSize, weight: .regular))
                    .foregroundStyle(PanelPalette.title)
                Text(status.detail)
                    .font(.system(size: PanelMetrics.metaSize, weight: .regular))
                    .foregroundStyle(PanelPalette.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if status.isError {
                Button("Retry", action: retry)
                    .font(.system(size: PanelMetrics.metaSize, weight: .regular))
                    .buttonStyle(.plain)
                    .foregroundStyle(PanelPalette.title)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
            }
        }
        .panelStatusRow()
        .accessibilityElement(children: .contain)
    }
}

struct HookRestartRow: View {
    let showsCodexTrustStep: Bool

    var body: some View {
        HStack(spacing: PanelMetrics.glyphGap) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(PanelPalette.working)
                .frame(width: PanelMetrics.glyphSize, height: PanelMetrics.glyphSize)

            VStack(alignment: .leading, spacing: PanelMetrics.textLineGap) {
                Text("Finish connecting your agents")
                    .font(.system(size: PanelMetrics.actionSize, weight: .regular))
                    .foregroundStyle(PanelPalette.title)
                Text(subtitle)
                    .font(.system(size: PanelMetrics.metaSize, weight: .regular))
                    .foregroundStyle(PanelPalette.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)
        }
        .panelStatusRow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Finish connecting your agents. \(subtitle).")
    }

    private var subtitle: String {
        if showsCodexTrustStep { return "Restart Codex, then trust hooks in /hooks" }
        return "Restart agents to start live updates"
    }
}

struct AvailableUpdateRow: View {
    let version: String
    let showUpdate: () -> Void

    var body: some View {
        Button(action: showUpdate) {
            HStack(spacing: PanelMetrics.glyphGap) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(PanelPalette.working)
                    .frame(width: PanelMetrics.glyphSize, height: PanelMetrics.glyphSize)

                VStack(alignment: .leading, spacing: PanelMetrics.textLineGap) {
                    Text("Update CodeWindow to \(version)")
                        .font(.system(size: PanelMetrics.actionSize, weight: .regular))
                        .foregroundStyle(PanelPalette.title)
                    Text("Click to review and install")
                        .font(.system(size: PanelMetrics.metaSize, weight: .regular))
                        .foregroundStyle(PanelPalette.meta)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
            }
            .panelStatusRow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Update to CodeWindow \(version)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Update CodeWindow to \(version)")
        .accessibilityHint("Opens the updater to review and install the latest version")
    }
}
