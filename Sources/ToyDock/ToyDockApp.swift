import AppKit
import SwiftUI

@main
struct ToyDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let dockTracker = DockTracker()
    private let widgetLayout = WidgetLayout()
    private var panel: NSPanel?
    private var dockGeometry: DockGeometry?
    private var dragSession: PanelDragSession?
    private var hoverExitTask: Task<Void, Never>?
    private(set) var panelState = WidgetPanelState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        #if DEBUG
        DockMetrics.selfCheck()
        WidgetPlacement.selfCheck()
        WidgetPanelState.selfCheck()
        WidgetLayout.selfCheck()
        PanelDragSession.selfCheck()
        #endif

        let initialPanelSize = widgetLayout.fallbackPanelSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initialPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: WidgetContentView(
            state: panelState,
            shadowPadding: widgetLayout.shadowPadding,
            onInteraction: { [weak self] interaction in
                self?.handle(interaction)
            }
        ))

        self.panel = panel
        DockTracker.requestAccessibilityAuthorization()
        dockTracker.start(
            screenProvider: { [weak panel] in
                panel?.screen ?? NSScreen.main ?? NSScreen.screens.first
            },
            onChange: { [weak self] geometry in
                self?.dockGeometry = geometry
                self?.updatePanel(
                    animated: false,
                    spring: self?.panel?.isVisible == true
                        ? .spring(duration: 0.2, bounce: 0)
                        : nil
                )
            }
        )
        panel.orderFrontRegardless()
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        dockTracker.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hoverExitTask?.cancel()
        dockTracker.stop()
    }

    func setWidgetPlacement(_ placement: WidgetPlacement, animated: Bool = true) {
        guard panelState.placement != placement else { return }
        relocateWidget(to: placement, animated: animated)
    }

    func setWidgetPresentation(_ presentation: WidgetPresentation, animated: Bool = true) {
        guard panelState.setPresentation(presentation) else { return }
        updatePanel(
            animated: animated,
            spring: animated ? .spring(duration: 0.2, bounce: 0.2) : nil
        )
    }

    func toggleWidgetPresentation(animated: Bool = true) {
        guard panelState.togglePresentation() else { return }
        updatePanel(
            animated: animated,
            spring: animated ? .spring(duration: 0.2, bounce: 0.2) : nil
        )
    }

    private func setWidgetHovered(_ isHovered: Bool) {
        guard panelState.setHovered(isHovered) else { return }
        updatePanel(
            animated: true,
            spring: .spring(duration: 0.2, bounce: 0.2),
            completion: { [weak self] in
                guard let self, self.hoverExitTask == nil else { return }
                self.reconcileHover()
            }
        )
    }

    private func handleHoverChanged(_ isHovered: Bool) {
        hoverExitTask?.cancel()
        hoverExitTask = nil
        guard panelState.movement == .idle else { return }

        guard !isHovered else {
            setWidgetHovered(true)
            return
        }

        hoverExitTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.hoverExitTask = nil
            self.reconcileHover()
        }
    }

    private func reconcileHover() {
        guard panelState.movement == .idle, let panel else { return }
        let interactionFrame = panel.frame.insetBy(
            dx: widgetLayout.shadowPadding,
            dy: widgetLayout.shadowPadding
        )
        setWidgetHovered(interactionFrame.contains(NSEvent.mouseLocation))
    }

    private func handle(_ interaction: WidgetInteraction) {
        switch interaction {
        case .hoverChanged(let isHovered):
            handleHoverChanged(isHovered)
        case .dragStarted:
            let mouseOrigin = NSEvent.mouseLocation
            guard beginWidgetRepositioning(), let panel else { return }
            dragSession = PanelDragSession(
                mouseOrigin: mouseOrigin,
                panelOrigin: panel.frame.origin
            )
        case .dragChanged:
            guard let panel, let dragSession else { return }
            panel.setFrameOrigin(dragSession.panelOrigin(at: NSEvent.mouseLocation))
        case .dragEnded:
            dragSession = nil
            guard let panel else { return }
            snapWidget(from: panel.frame)
        }
    }

    private func beginWidgetRepositioning() -> Bool {
        guard let panel, let dockGeometry else { return false }

        hoverExitTask?.cancel()
        hoverExitTask = nil
        panelState.beginRepositioning(to: panelState.placement)
        let compactSize = widgetLayout.panelFrame(
            dock: dockGeometry,
            placement: panelState.placement,
            presentation: .compact
        ).size
        panel.setFrame(
            CGRect(
                x: panel.frame.midX - compactSize.width / 2,
                y: panel.frame.midY - compactSize.height / 2,
                width: compactSize.width,
                height: compactSize.height
            ),
            display: true
        )
        return true
    }

    private func snapWidget(from frame: CGRect) {
        guard let dockGeometry else { return }
        let placement = widgetLayout.placement(
            for: frame,
            relativeTo: dockGeometry,
            keeping: panelState.placement
        )
        relocateWidget(to: placement, animated: true)
    }

    private func relocateWidget(
        to placement: WidgetPlacement,
        animated: Bool
    ) {
        hoverExitTask?.cancel()
        hoverExitTask = nil
        panelState.beginRepositioning(to: placement)
        updatePanel(
            animated: false,
            spring: animated ? .spring(duration: 0.35, bounce: 0.3) : nil,
            completion: { [weak self] in
                guard let self else { return }
                self.panelState.finishRepositioning()
                self.reconcileHover()
            }
        )
    }

    private func updatePanel(
        animated: Bool,
        spring: Animation? = nil,
        completion: (() -> Void)? = nil
    ) {
        guard let panel, let dockGeometry else {
            completion?()
            return
        }
        panelState.updateDockEdge(dockGeometry.edge)
        let nextFrame = widgetLayout.panelFrame(
            dock: dockGeometry,
            placement: panelState.placement,
            presentation: panelState.presentation
        )
        guard panel.frame != nextFrame else {
            completion?()
            return
        }

        if let spring {
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                panel.setFrame(nextFrame, display: true)
                completion?()
                return
            }

            NSAnimationContext.animate(spring) {
                panel.setFrame(nextFrame, display: true)
            } completion: {
                completion?()
            }
            return
        }

        panel.setFrame(nextFrame, display: true, animate: animated)
        completion?()
    }
}

private struct PanelDragSession {
    let mouseOrigin: CGPoint
    let panelOrigin: CGPoint

    func panelOrigin(at mouseLocation: CGPoint) -> CGPoint {
        CGPoint(
            x: panelOrigin.x + mouseLocation.x - mouseOrigin.x,
            y: panelOrigin.y + mouseLocation.y - mouseOrigin.y
        )
    }

    static func selfCheck() {
        let session = PanelDragSession(
            mouseOrigin: CGPoint(x: 100, y: 80),
            panelOrigin: CGPoint(x: 300, y: 20)
        )
        assert(session.panelOrigin(at: CGPoint(x: 140, y: 65)) == CGPoint(x: 340, y: 5))
    }
}
