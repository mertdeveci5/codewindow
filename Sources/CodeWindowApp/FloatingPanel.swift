import AppKit

/// A borderless, non-activating panel that floats above every Space and over
/// full-screen apps. It never takes key or main status, so clicking or dragging
/// it never steals focus from the terminal the user is working in.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
