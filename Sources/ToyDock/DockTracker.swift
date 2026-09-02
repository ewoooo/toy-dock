import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics

enum DockEdge: Equatable {
    case bottom
    case left
    case right
}

struct DockGeometry: Equatable {
    let edge: DockEdge
    let frame: CGRect
    let thickness: CGFloat
    let screenFrame: CGRect
    let isEstimated: Bool
}

final class DockTracker: NSObject {
    private static let fallbackPollInterval: TimeInterval = 0.5
    private static let recoveryPollInterval: TimeInterval = 2
    private static let observationSettleInterval: TimeInterval = 0.08

    private var timer: Timer?
    private var settleTimer: Timer?
    private var pollInterval: TimeInterval?
    private var observer: AXObserver?
    private var observedElement: AXUIElement?
    private var observedProcessIdentifier: pid_t?
    private var registeredNotifications: [CFString] = []
    private var screenProvider: (() -> NSScreen?)?
    private var onChange: ((DockGeometry) -> Void)?
    private(set) var geometry: DockGeometry?

    func start(
        screenProvider: @escaping () -> NSScreen?,
        onChange: @escaping (DockGeometry) -> Void
    ) {
        stop()
        self.screenProvider = screenProvider
        self.onChange = onChange
        refresh()
    }

    func stop() {
        timer?.invalidate()
        settleTimer?.invalidate()
        timer = nil
        settleTimer = nil
        pollInterval = nil
        removeObserver()
        geometry = nil
        screenProvider = nil
        onChange = nil
    }

    func refresh() {
        let nextGeometry: DockGeometry?
        if let measurement = measuredDock() {
            installObserver(
                for: measurement.element,
                processIdentifier: measurement.processIdentifier
            )
            nextGeometry = measurement.geometry
        } else {
            nextGeometry = screenProvider?().map(estimatedGeometry(on:))
        }
        updatePolling()

        guard let nextGeometry else { return }
        guard geometry != nextGeometry else { return }
        geometry = nextGeometry
        onChange?(nextGeometry)
    }

    @discardableResult
    static func requestAccessibilityAuthorization() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static var isAccessibilityAuthorized: Bool {
        AXIsProcessTrusted()
    }

    @objc private func poll() {
        refresh()
    }

    @objc private func refreshAfterObservedChange() {
        settleTimer = nil
        refresh()
    }

    private func scheduleObservedRefresh() {
        settleTimer?.invalidate()
        let timer = Timer(
            timeInterval: Self.observationSettleInterval,
            target: self,
            selector: #selector(refreshAfterObservedChange),
            userInfo: nil,
            repeats: false
        )
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
    }

    private func updatePolling() {
        let nextInterval = observer == nil
            ? Self.fallbackPollInterval
            : Self.recoveryPollInterval
        guard pollInterval != nextInterval else { return }

        timer?.invalidate()
        let timer = Timer(
            timeInterval: nextInterval,
            target: self,
            selector: #selector(poll),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        pollInterval = nextInterval
    }

    private func installObserver(for element: AXUIElement, processIdentifier: pid_t) {
        guard observedProcessIdentifier != processIdentifier else { return }

        removeObserver()

        var nextObserver: AXObserver?
        let result = AXObserverCreate(
            processIdentifier,
            { _, _, _, context in
                guard let context else { return }
                MainActor.assumeIsolated {
                    Unmanaged<DockTracker>
                        .fromOpaque(context)
                        .takeUnretainedValue()
                        .scheduleObservedRefresh()
                }
            },
            &nextObserver
        )
        guard result == .success, let nextObserver else { return }

        let runLoopSource = AXObserverGetRunLoopSource(nextObserver)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let notifications = [
            kAXResizedNotification as CFString,
            kAXMovedNotification as CFString,
            kAXLayoutChangedNotification as CFString,
        ]
        let registeredNotifications = notifications.filter {
            AXObserverAddNotification(nextObserver, element, $0, context) == .success
        }
        guard !registeredNotifications.isEmpty else {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            return
        }
        observer = nextObserver
        observedElement = element
        observedProcessIdentifier = processIdentifier
        self.registeredNotifications = registeredNotifications
    }

    private func removeObserver() {
        guard let observer else { return }

        if let observedElement {
            for notification in registeredNotifications {
                AXObserverRemoveNotification(observer, observedElement, notification)
            }
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        self.observer = nil
        observedElement = nil
        observedProcessIdentifier = nil
        registeredNotifications = []
    }

    private func measuredDock() -> (
        geometry: DockGeometry,
        element: AXUIElement,
        processIdentifier: pid_t
    )? {
        guard Self.isAccessibilityAuthorized,
              let application = NSRunningApplication.runningApplications(
                  withBundleIdentifier: "com.apple.dock"
              ).first
        else { return nil }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let dockList = firstList(in: applicationElement),
              let accessibilityFrame = frame(of: dockList),
              let screen = screen(containing: accessibilityFrame),
              let frame = appKitFrame(from: accessibilityFrame, on: screen)
        else { return nil }

        let edge = nearestDockEdge(to: frame, on: screen)
        let thickness = edge == .bottom ? frame.height : frame.width
        guard thickness > 0 else { return nil }

        return (
            DockGeometry(
                edge: edge,
                frame: frame,
                thickness: thickness,
                screenFrame: screen.frame,
                isEstimated: false
            ),
            applicationElement,
            application.processIdentifier
        )
    }

    private func estimatedGeometry(on screen: NSScreen) -> DockGeometry {
        let frame = screen.frame
        let visibleFrame = screen.visibleFrame
        let insets: [(DockEdge, CGFloat)] = [
            (.bottom, visibleFrame.minY - frame.minY),
            (.left, visibleFrame.minX - frame.minX),
            (.right, frame.maxX - visibleFrame.maxX),
        ]
        let (edge, occupiedInset) = insets.max(by: { $0.1 < $1.1 }) ?? (.bottom, 0)
        let thickness = DockMetrics.widgetSide(occupiedInset: occupiedInset)

        // ponytail: visibleFrame has no Dock length; Accessibility replaces this centered estimate when authorized.
        let axisLength = edge == .bottom ? frame.width : frame.height
        let dockLength = axisLength * DockMetrics.estimatedLengthRatio
        let dockFrame: CGRect

        switch edge {
        case .bottom:
            dockFrame = CGRect(
                x: frame.midX - dockLength / 2,
                y: frame.minY + DockMetrics.screenEdgeGap,
                width: dockLength,
                height: thickness
            )
        case .left:
            dockFrame = CGRect(
                x: frame.minX + DockMetrics.screenEdgeGap,
                y: frame.midY - dockLength / 2,
                width: thickness,
                height: dockLength
            )
        case .right:
            dockFrame = CGRect(
                x: frame.maxX - DockMetrics.screenEdgeGap - thickness,
                y: frame.midY - dockLength / 2,
                width: thickness,
                height: dockLength
            )
        }

        return DockGeometry(
            edge: edge,
            frame: dockFrame,
            thickness: thickness,
            screenFrame: frame,
            isEstimated: true
        )
    }

    private func firstList(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if attribute(element, kAXRoleAttribute as CFString) as? String == kAXListRole as String {
            return element
        }
        guard depth < 2,
              let children = attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement]
        else { return nil }

        return children.lazy.compactMap { self.firstList(in: $0, depth: depth + 1) }.first
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position = axValue(element, kAXPositionAttribute as CFString),
              let size = axValue(element, kAXSizeAttribute as CFString)
        else { return nil }

        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(size, .cgSize, &dimensions)
        else { return nil }

        return CGRect(origin: origin, size: dimensions)
    }

    private func screen(containing accessibilityFrame: CGRect) -> NSScreen? {
        let center = CGPoint(x: accessibilityFrame.midX, y: accessibilityFrame.midY)
        return NSScreen.screens.first { screen in
            guard let displayID = displayID(for: screen) else { return false }
            return CGDisplayBounds(displayID).contains(center)
        }
    }

    private func appKitFrame(from accessibilityFrame: CGRect, on screen: NSScreen) -> CGRect? {
        guard let displayID = displayID(for: screen) else { return nil }
        let displayFrame = CGDisplayBounds(displayID)
        return CGRect(
            x: screen.frame.minX + accessibilityFrame.minX - displayFrame.minX,
            y: screen.frame.minY + displayFrame.maxY - accessibilityFrame.maxY,
            width: accessibilityFrame.width,
            height: accessibilityFrame.height
        )
    }

    private func nearestDockEdge(to dockFrame: CGRect, on screen: NSScreen) -> DockEdge {
        let distances: [(DockEdge, CGFloat)] = [
            (.bottom, abs(dockFrame.minY - screen.frame.minY)),
            (.left, abs(dockFrame.minX - screen.frame.minX)),
            (.right, abs(screen.frame.maxX - dockFrame.maxX)),
        ]
        return distances.min(by: { $0.1 < $1.1 })?.0 ?? .bottom
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }

    private func axValue(_ element: AXUIElement, _ name: CFString) -> AXValue? {
        guard let value = attribute(element, name),
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXValue.self)
    }
}
