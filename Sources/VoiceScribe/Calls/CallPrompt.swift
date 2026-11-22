import AppKit
import SwiftUI

/// A small card in the top-right corner (where notifications appear) that says an app
/// is using the microphone and offers to record. Clickable, but never steals focus.
final class CallPromptController {
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?
    private(set) var appID: String?

    private let size = NSSize(width: 340, height: 64)
    /// Vertical offset from the top-right corner, so a second card can sit below the first
    private let verticalOffset: CGFloat

    init(verticalOffset: CGFloat = 0) {
        self.verticalOffset = verticalOffset
    }

    /// General-purpose card
    func show(id: String? = nil, icon: String, colour: Color, title: String, subtitle: String,
              primary: (String, () -> Void), secondary: (String, () -> Void)?,
              autoDismissAfter: TimeInterval?) {
        let wrap: (@escaping () -> Void) -> () -> Void = { action in { [weak self] in self?.dismiss(); action() } }
        present(id: id, view: CallPromptView(
            icon: icon, iconColour: colour, title: title, subtitle: subtitle,
            primary: (primary.0, wrap(primary.1)),
            secondary: secondary.map { ($0.0, wrap($0.1)) }
        ), autoDismissAfter: autoDismissAfter)
    }

    /// Ask whether to record
    func ask(_ app: WatchedApp, onRecord: @escaping () -> Void, onIgnore: @escaping () -> Void) {
        let message = app.isBrowser ? "\(app.name) is using the microphone" : "\(app.name) call detected"
        present(app, view: CallPromptView(
            icon: app.isBrowser ? "exclamationmark.triangle.fill" : "phone.fill",
            iconColour: app.isBrowser ? .orange : .green,
            title: message,
            subtitle: "Record and transcribe it?",
            primary: ("Record", { [weak self] in self?.dismiss(); onRecord() }),
            secondary: ("Ignore", { [weak self] in self?.dismiss(); onIgnore() })
        ), autoDismissAfter: nil)
    }

    /// Tell the user recording started automatically
    func notifyAutoRecording(_ app: WatchedApp, onStop: @escaping () -> Void) {
        present(app, view: CallPromptView(
            icon: "record.circle.fill",
            iconColour: .red,
            title: "Recording \(app.name)",
            subtitle: "Stops when the call ends",
            primary: ("Stop", { [weak self] in self?.dismiss(); onStop() }),
            secondary: ("OK", { [weak self] in self?.dismiss() })
        ), autoDismissAfter: 6)
    }

    func dismiss() {
        dismissWork?.cancel()
        appID = nil
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func present(_ app: WatchedApp, view: CallPromptView, autoDismissAfter: TimeInterval?) {
        present(id: app.id, view: view, autoDismissAfter: autoDismissAfter)
    }

    private func present(id: String?, view: CallPromptView, autoDismissAfter: TimeInterval?) {
        dismissWork?.cancel()
        appID = id
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: view)
        position(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
        if let delay = autoDismissAfter {
            let work = DispatchWorkItem { [weak self] in self?.dismiss() }
            dismissWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
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
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrame(NSRect(
            x: frame.maxX - size.width - 16,
            y: frame.maxY - size.height - 12 - verticalOffset,
            width: size.width, height: size.height
        ), display: true)
    }
}

struct CallPromptView: View {
    let icon: String
    let iconColour: Color
    let title: String
    let subtitle: String
    let primary: (String, () -> Void)
    let secondary: (String, () -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColour)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let secondary {
                Button(secondary.0, action: secondary.1)
                    .controlSize(.small)
            }
            Button(primary.0, action: primary.1)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .frame(width: 340, height: 64)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }
}
