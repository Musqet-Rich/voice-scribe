import AppKit
import ApplicationServices
import SwiftUI

/// What the pill is showing
enum PillState: Equatable {
    case hidden, listening, transcribing
}

/// Drives the pill view. Kept separate from AppState so 30fps level updates
/// don't re-render the rest of the app.
final class PillModel: ObservableObject {
    @Published var state: PillState = .hidden
    @Published var level: CGFloat = 0
}

/// A small floating capsule at the bottom centre of the screen you're working on,
/// showing live audio waves while listening. Never takes focus or clicks.
final class PillController {
    let model = PillModel()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    private let size = NSSize(width: 132 * PillView.scale, height: 38 * PillView.scale)
    private let bottomMargin: CGFloat = 24

    func show(_ state: PillState) {
        hideWork?.cancel()
        model.state = state
        if state == .listening { model.level = 0 }

        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                panel.animator().alphaValue = 0
            }, completionHandler: {
                guard self?.model.state == .hidden else { return }
                panel.orderOut(nil)
            })
        }
        model.state = .hidden
        hideWork = work
        DispatchQueue.main.async(execute: work)
    }

    /// Smoothed mic level, 0...1
    func setLevel(_ level: Float) {
        let target = CGFloat(level)
        // Fast attack, slower release, so speech looks lively without flicker
        let k: CGFloat = target > model.level ? 0.6 : 0.25
        model.level += (target - model.level) * k
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: PillView(model: model))
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screen = Self.focusedScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrame(NSRect(
            x: frame.midX - size.width / 2,
            y: frame.minY + bottomMargin,
            width: size.width,
            height: size.height
        ), display: true)
    }

    /// The screen holding the focused window of the frontmost app (via Accessibility),
    /// falling back to the screen under the mouse.
    private static func focusedScreen() -> NSScreen? {
        if let app = NSWorkspace.shared.frontmostApplication {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
               let windowRef {
                let window = windowRef as! AXUIElement
                var posRef: CFTypeRef?, sizeRef: CFTypeRef?
                var pos = CGPoint.zero, sz = CGSize.zero
                if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
                   AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
                   let posRef, let sizeRef,
                   AXValueGetValue(posRef as! AXValue, .cgPoint, &pos),
                   AXValueGetValue(sizeRef as! AXValue, .cgSize, &sz) {
                    // AX uses top-left origin on the primary screen; convert to Cocoa coordinates
                    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
                    let centre = CGPoint(x: pos.x + sz.width / 2, y: primaryHeight - (pos.y + sz.height / 2))
                    if let screen = NSScreen.screens.first(where: { $0.frame.contains(centre) }) {
                        return screen
                    }
                }
            }
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }
}

/// The capsule itself
struct PillView: View {
    /// Overall size of the pill relative to its 132x38 design
    static let scale: CGFloat = 0.5

    @ObservedObject var model: PillModel

    var body: some View {
        ZStack {
            Capsule()
                .fill(.black.opacity(0.82))
                .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))

            switch model.state {
            case .listening:
                WaveBars(level: model.level)
            case .transcribing:
                WorkingDots()
            case .hidden:
                EmptyView()
            }
        }
        .frame(width: 132, height: 38)
        .scaleEffect(Self.scale)
        .frame(width: 132 * Self.scale, height: 38 * Self.scale)
    }
}

/// Bars that respond to the mic level, with a gentle idle ripple so you can tell it's live in silence
struct WaveBars: View {
    let level: CGFloat
    private let count = 11
    // Centre-weighted so the shape reads as a voice wave
    private let weights: [CGFloat] = [0.35, 0.5, 0.65, 0.8, 0.92, 1.0, 0.92, 0.8, 0.65, 0.5, 0.35]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3.5) {
                ForEach(0..<count, id: \.self) { i in
                    let wobble = 0.5 + 0.5 * sin(t * 7 + Double(i) * 0.8)
                    let idle: CGFloat = 0.10 + 0.06 * CGFloat(wobble)
                    let speech = level * weights[i] * (0.65 + 0.35 * CGFloat(wobble))
                    Capsule()
                        .fill(.white.opacity(0.95))
                        .frame(width: 3.5, height: 4 + 20 * max(idle, speech))
                }
            }
            .animation(.linear(duration: 1.0 / 30), value: level)
        }
    }
}

/// Three pulsing dots while the speech model works
struct WorkingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = 0.5 + 0.5 * sin(t * 6 - Double(i) * 0.9)
                    Circle()
                        .fill(.white.opacity(0.4 + 0.6 * phase))
                        .frame(width: 6, height: 6)
                        .scaleEffect(0.8 + 0.3 * phase)
                }
            }
        }
    }
}
