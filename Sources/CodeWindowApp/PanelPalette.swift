import AppKit
import SwiftUI

enum PanelPalette {
    /// The opaque surface used when Reduce Transparency turns glass off.
    static let surface = Color(red: 0.025, green: 0.025, blue: 0.029)
    /// The docked island borrows the housing's own black so the seam disappears.
    static let island = Color.black
    /// Smoke laid over the floating glass so it stays as dark as the island it docks into.
    static let glassTint = Color.black.opacity(0.4)
    /// Semantic label colors resolve against the panel's dark appearance and stay vibrant
    /// over glass, where fixed white opacities would read flat.
    static let title = Color.primary
    static let meta = Color.secondary
    static let diagnostic = Color.primary.opacity(0.64)
    static let attention = Color(nsColor: .systemOrange)
    static let working = Color(nsColor: .systemGreen)
    static let starting = Color(nsColor: .systemBlue)
    static let muted = Color(nsColor: .tertiaryLabelColor)
    static let divider = Color(nsColor: .separatorColor)
    static let rowHover = Color.white.opacity(0.07)

    static func statusColor(for session: PresentedSession) -> Color {
        if session.isDiagnostic { return attention.opacity(0.55) }
        return switch session.activity {
        case .needsAttention: attention
        case .working: working
        case .starting: starting
        case .idle, .ended: muted
        }
    }
}
