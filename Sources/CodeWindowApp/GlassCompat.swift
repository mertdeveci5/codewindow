import AppKit
import SwiftUI

/// Liquid Glass on macOS 26, a dark behind-window material before it. Views ask for a glass
/// surface or button here and never call the macOS 26 APIs directly, so the app still builds
/// with older toolchains and still runs on macOS 13.
extension View {
    @ViewBuilder
    func cwGlassSurface<S: InsettableShape>(
        in shape: S,
        reduceTransparency: Bool,
        increasedContrast: Bool
    ) -> some View {
        let hairline = Color.white.opacity(increasedContrast ? 0.28 : 0.09)
        if reduceTransparency {
            self
                .background(PanelPalette.surface, in: shape)
                .overlay { shape.strokeBorder(hairline, lineWidth: 0.75).accessibilityHidden(true) }
        } else {
            modernGlass(in: shape, hairline: hairline)
        }
    }

    @ViewBuilder
    private func modernGlass<S: InsettableShape>(in shape: S, hairline: Color) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            // A smoked tint keeps the panel as dark as the island it docks into, while the
            // glass still picks up the light and color of whatever sits behind it.
            self.glassEffect(.regular.tint(PanelPalette.glassTint), in: shape)
        } else {
            materialGlass(in: shape, hairline: hairline)
        }
        #else
        materialGlass(in: shape, hairline: hairline)
        #endif
    }

    private func materialGlass<S: InsettableShape>(in shape: S, hairline: Color) -> some View {
        background {
            VisualEffectBackground()
                .clipShape(shape)
                .accessibilityHidden(true)
        }
        .overlay {
            // The top edge catches a little more light than the sides, like a glass lip.
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [hairline.opacity(1.6), hairline.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
                .accessibilityHidden(true)
        }
    }

    /// A small capsule action inside a panel row.
    @ViewBuilder
    func cwGlassButton(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            if prominent {
                self.buttonStyle(.glassProminent).tint(PanelPalette.working)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            buttonStyle(CapsuleActionButtonStyle())
        }
        #else
        buttonStyle(CapsuleActionButtonStyle())
        #endif
    }
}

struct CapsuleActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: PanelMetrics.metaSize, weight: .medium))
            .foregroundStyle(PanelPalette.title)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0.10)))
            .contentShape(Capsule())
    }
}

/// The pre-Tahoe stand-in for glass: a dark HUD material blended with what is behind the window.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Motion shared by everything that grows out of the island.
enum IslandMotion {
    /// Opening carries a little overshoot, the way the island springs out of the hardware.
    static let expand = Animation.spring(response: 0.42, dampingFraction: 0.76)
    /// Closing is settled and quick, with no bounce back past its resting size.
    static let collapse = Animation.spring(response: 0.34, dampingFraction: 0.92)
    /// Long enough for either spring to come to rest before the window shrinks to fit.
    static let settleDelay: TimeInterval = 0.62

    static let present = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let dismiss = Animation.easeIn(duration: 0.12)
}

/// Content entering or leaving the island blurs through the change instead of popping, so
/// a state change reads as the same object refocusing.
private struct BlurFade: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(1 - progress)
            .blur(radius: 7 * progress)
            .scaleEffect(1 - 0.06 * progress, anchor: .top)
    }
}

extension AnyTransition {
    static var islandContent: AnyTransition {
        .modifier(active: BlurFade(progress: 1), identity: BlurFade(progress: 0))
    }
}
