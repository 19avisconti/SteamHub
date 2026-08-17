import AppKit

/// Shows achievement toasts one at a time in the bottom-right corner, Steam-style:
/// slide up, hold, fade out — with the achievement chime on appearance.
/// Main thread only.
final class ToastPresenter {
    static let shared = ToastPresenter()

    private enum Timing {
        static let slideIn: TimeInterval = 0.35
        static let hold: TimeInterval = 5.0
        static let fadeOut: TimeInterval = 0.45
    }

    /// Notification size in points. The artwork is 1920x768, so height follows from the width.
    private let width: CGFloat = 420
    private var height: CGFloat { width * 768.0 / 1920.0 }
    private let margin: CGFloat = 12

    /// Pending toasts beyond this are dropped rather than queued for minutes on end.
    private let maxQueued = 12

    private lazy var background: NSImage? = Bundle.module
        .url(forResource: "full-achievement", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }

    private lazy var sound: NSSound? = Bundle.module
        .url(forResource: "steam-achievement", withExtension: "mp3")
        .flatMap { NSSound(contentsOf: $0, byReference: true) }

    private var queue: [(title: String, body: String)] = []
    private var window: ToastWindow?
    private var dismissWork: DispatchWorkItem?

    func show(title: String, body: String) {
        guard queue.count < maxQueued else { return }
        queue.append((title, body))
        if window == nil { presentNext() }
    }

    func show(_ event: PushEvent) {
        show(title: event.author, body: event.message)
    }

    // MARK: - Presentation

    /// The display the user is looking at. A menu-bar app has no key window, so
    /// `NSScreen.main` is unreliable across multiple displays — follow the cursor instead.
    private var activeScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    private func presentNext() {
        guard !queue.isEmpty else { return }
        let item = queue.removeFirst()

        guard let screen = activeScreen else { return }
        let visible = screen.visibleFrame
        let size = NSSize(width: width, height: height)
        let endOrigin = NSPoint(x: visible.maxX - size.width - margin, y: visible.minY + margin)
        let startOrigin = NSPoint(x: endOrigin.x, y: visible.minY - size.height)

        let view = AchievementView(frame: NSRect(origin: .zero, size: size), background: background)
        view.title = item.title
        view.body = item.body

        let w = ToastWindow(contentRect: NSRect(origin: startOrigin, size: size))
        w.contentView = view
        w.onClick = { [weak self] in self?.dismiss() }
        w.alphaValue = 0
        w.orderFrontRegardless()
        window = w

        sound?.stop()
        sound?.play()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Timing.slideIn
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            // NSWindow's animator only animates `frame` and `alphaValue` —
            // setFrameOrigin(_:) through the proxy is a no-op.
            w.animator().setFrame(NSRect(origin: endOrigin, size: size), display: true)
            w.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.slideIn + Timing.hold, execute: work)
    }

    private func dismiss() {
        dismissWork?.cancel()
        dismissWork = nil
        guard let w = window else { return }
        window = nil

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Timing.fadeOut
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            w.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            w.orderOut(nil)
            self?.presentNext()
        }
    }
}

/// Borderless, non-activating panel that floats above other windows and every Space.
private final class ToastWindow: NSPanel {
    var onClick: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) { onClick?() }
}
