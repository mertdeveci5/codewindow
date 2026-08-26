import SwiftUI

enum PanelPalette {
    static let surface = Color(red: 0.025, green: 0.025, blue: 0.029)
    /// The docked island borrows the housing's own black so the seam disappears.
    static let island = Color.black
    static let title = Color.white.opacity(0.96)
    static let meta = Color.white.opacity(0.48)
    static let diagnostic = Color.white.opacity(0.64)
    static let attention = Color(nsColor: .systemOrange)
    static let working = Color(nsColor: .systemGreen)
    static let starting = Color(nsColor: .systemBlue)
    static let muted = Color.white.opacity(0.30)
    static let divider = Color.white.opacity(0.075)

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
