import CoreGraphics
import Observation

enum WidgetPlacement: Equatable {
    case beforeDock
    case afterDock

    func expansionDirection(for dockEdge: DockEdge) -> WidgetExpansionDirection {
        switch (dockEdge, self) {
        case (.bottom, .beforeDock): .left
        case (.bottom, .afterDock): .right
        case (.left, .beforeDock), (.right, .beforeDock): .up
        case (.left, .afterDock), (.right, .afterDock): .down
        }
    }

    func originCorner(for dockEdge: DockEdge) -> WidgetCorner {
        switch (dockEdge, self) {
        case (.bottom, .beforeDock), (.right, .beforeDock): .bottomRight
        case (.bottom, .afterDock), (.left, .beforeDock): .bottomLeft
        case (.right, .afterDock): .topRight
        case (.left, .afterDock): .topLeft
        }
    }

    static func selfCheck() {
        assert(WidgetPlacement.beforeDock.expansionDirection(for: .bottom) == .left)
        assert(WidgetPlacement.afterDock.expansionDirection(for: .bottom) == .right)
        assert(WidgetPlacement.beforeDock.expansionDirection(for: .left) == .up)
        assert(WidgetPlacement.afterDock.expansionDirection(for: .left) == .down)
        assert(WidgetPlacement.beforeDock.expansionDirection(for: .right) == .up)
        assert(WidgetPlacement.afterDock.expansionDirection(for: .right) == .down)
        assert(WidgetPlacement.beforeDock.originCorner(for: .bottom) == .bottomRight)
        assert(WidgetPlacement.afterDock.originCorner(for: .bottom) == .bottomLeft)
        assert(WidgetPlacement.beforeDock.originCorner(for: .left) == .bottomLeft)
        assert(WidgetPlacement.afterDock.originCorner(for: .right) == .topRight)
    }
}

enum WidgetCorner: Equatable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    nonisolated var isLeft: Bool {
        switch self {
        case .topLeft, .bottomLeft: true
        case .topRight, .bottomRight: false
        }
    }

    nonisolated var isTop: Bool {
        switch self {
        case .topLeft, .topRight: true
        case .bottomLeft, .bottomRight: false
        }
    }
}

enum WidgetExpansionDirection: Equatable {
    case up
    case down
    case left
    case right
}

enum WidgetPresentation: Equatable {
    case compact
    case expanded

    mutating func toggle() {
        self = switch self {
        case .compact: .expanded
        case .expanded: .compact
        }
    }
}

enum WidgetMovementState: Equatable {
    case idle
    case repositioning
}

@Observable
final class WidgetPanelState {
    private(set) var presentation = WidgetPresentation.compact
    private(set) var placement = WidgetPlacement.afterDock
    private(set) var movement = WidgetMovementState.idle
    private(set) var dockEdge = DockEdge.bottom
    private(set) var repositioningSurfaceSize: CGSize?
    func setPresentation(_ presentation: WidgetPresentation) -> Bool {
        guard movement == .idle, self.presentation != presentation else { return false }
        self.presentation = presentation
        return true
    }

    func togglePresentation() -> Bool {
        guard movement == .idle else { return false }
        presentation.toggle()
        return true
    }

    func setHovered(_ isHovered: Bool) -> Bool {
        return setPresentation(isHovered ? .expanded : .compact)
    }

    func beginRepositioning(to placement: WidgetPlacement, surfaceSize: CGSize) {
        presentation = .compact
        self.placement = placement
        movement = .repositioning
        repositioningSurfaceSize = surfaceSize
    }

    func finishRepositioning() {
        movement = .idle
        repositioningSurfaceSize = nil
    }

    func updateDockEdge(_ dockEdge: DockEdge) {
        self.dockEdge = dockEdge
    }

    static func selfCheck() {
        let state = WidgetPanelState()
        assert(state.setPresentation(.expanded))

        let compactSize = CGSize(width: 80, height: 80)
        state.beginRepositioning(to: .beforeDock, surfaceSize: compactSize)
        assert(state.presentation == .compact)
        assert(state.placement == .beforeDock)
        assert(state.movement == .repositioning)
        assert(state.repositioningSurfaceSize == compactSize)
        assert(!state.setPresentation(.expanded))

        state.finishRepositioning()
        assert(state.repositioningSurfaceSize == nil)
        assert(state.togglePresentation())
        assert(state.presentation == .expanded)
        assert(state.setHovered(false))
        assert(state.presentation == .compact)

        state.beginRepositioning(to: .afterDock, surfaceSize: compactSize)
        assert(state.presentation == .compact)
    }
}
