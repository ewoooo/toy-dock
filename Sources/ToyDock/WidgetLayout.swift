import AppKit

enum DockMetrics {
    static let screenEdgeGap: CGFloat = 6
    static let fallbackSide: CGFloat = 64
    static let shadowPadding: CGFloat = 16
    static let maximumSurfaceScale: CGFloat = 1.05
    static let estimatedLengthRatio: CGFloat = 0.26

    static func widgetSide(occupiedInset: CGFloat) -> CGFloat {
        let measuredSide = occupiedInset - screenEdgeGap
        return measuredSide > 0 ? measuredSide : fallbackSide
    }

    static func selfCheck() {
        assert(widgetSide(occupiedInset: 86) == 80)
        assert(widgetSide(occupiedInset: 0) == fallbackSide)
    }
}

struct WidgetLayout {
    let gap: CGFloat
    let dockBackgroundPadding: CGFloat
    let shadowPadding: CGFloat
    let expandedLengthMultiplier: CGFloat
    let expandedDepthMultiplier: CGFloat

    init(
        gap: CGFloat = 8,
        dockBackgroundPadding: CGFloat = 8,
        shadowPadding: CGFloat = DockMetrics.shadowPadding,
        expandedLengthMultiplier: CGFloat = 3.71,
        expandedDepthMultiplier: CGFloat = 1.61
    ) {
        self.gap = gap
        self.dockBackgroundPadding = dockBackgroundPadding
        self.shadowPadding = shadowPadding
        self.expandedLengthMultiplier = expandedLengthMultiplier
        self.expandedDepthMultiplier = expandedDepthMultiplier
    }

    var fallbackPanelSize: CGSize {
        let side = DockMetrics.fallbackSide * DockMetrics.maximumSurfaceScale
            + shadowPadding * 2
        return CGSize(width: side, height: side)
    }

    func panelFrame(
        dock: DockGeometry,
        placement: WidgetPlacement,
        presentation: WidgetPresentation
    ) -> CGRect {
        let content = contentFrame(
            dock: dock,
            placement: placement,
            presentation: presentation
        )
        let origin = placement.originCorner(for: dock.edge)
        let scaleOverflow = CGSize(
            width: content.width * (DockMetrics.maximumSurfaceScale - 1),
            height: content.height * (DockMetrics.maximumSurfaceScale - 1)
        )

        return CGRect(
            x: content.minX - shadowPadding - (origin.isLeft ? 0 : scaleOverflow.width),
            y: content.minY - shadowPadding - (origin.isTop ? scaleOverflow.height : 0),
            width: content.width + scaleOverflow.width + shadowPadding * 2,
            height: content.height + scaleOverflow.height + shadowPadding * 2
        )
    }

    func placement(
        for widgetFrame: CGRect,
        relativeTo dock: DockGeometry,
        keeping current: WidgetPlacement
    ) -> WidgetPlacement {
        switch dock.edge {
        case .bottom:
            guard widgetFrame.midX != dock.frame.midX else { return current }
            return widgetFrame.midX < dock.frame.midX ? .beforeDock : .afterDock
        case .left, .right:
            guard widgetFrame.midY != dock.frame.midY else { return current }
            return widgetFrame.midY > dock.frame.midY ? .beforeDock : .afterDock
        }
    }

    func contentFrame(
        dock: DockGeometry,
        placement: WidgetPlacement,
        presentation: WidgetPresentation
    ) -> CGRect {
        let side = dock.thickness > 0 ? dock.thickness : DockMetrics.fallbackSide
        let expandedLength = side * expandedLengthMultiplier
        let expandedDepth = side * expandedDepthMultiplier
        let size: CGSize

        switch (dock.edge, presentation) {
        case (_, .compact):
            size = CGSize(width: side, height: side)
        case (.bottom, .expanded):
            size = CGSize(width: expandedLength, height: expandedDepth)
        case (.left, .expanded), (.right, .expanded):
            size = CGSize(width: expandedDepth, height: expandedLength)
        }

        let dockFrame = dock.frame.insetBy(
            dx: -dockBackgroundPadding,
            dy: -dockBackgroundPadding
        )
        let screenEdgeOrigin: CGFloat = switch dock.edge {
        case .bottom:
            dock.screenFrame.minY + DockMetrics.screenEdgeGap
        case .left:
            dock.screenFrame.minX + DockMetrics.screenEdgeGap
        case .right:
            dock.screenFrame.maxX - DockMetrics.screenEdgeGap - size.width
        }
        let origin: CGPoint

        switch (dock.edge, placement) {
        case (.bottom, .beforeDock):
            origin = CGPoint(
                x: dockFrame.minX - gap - size.width,
                y: screenEdgeOrigin
            )
        case (.bottom, .afterDock):
            origin = CGPoint(
                x: dockFrame.maxX + gap,
                y: screenEdgeOrigin
            )
        case (.left, .beforeDock), (.right, .beforeDock):
            origin = CGPoint(
                x: screenEdgeOrigin,
                y: dockFrame.maxY + gap
            )
        case (.left, .afterDock), (.right, .afterDock):
            origin = CGPoint(
                x: screenEdgeOrigin,
                y: dockFrame.minY - gap - size.height
            )
        }

        return CGRect(origin: origin, size: size)
    }

    static func selfCheck() {
        let layout = WidgetLayout(
            gap: 10,
            dockBackgroundPadding: 0,
            shadowPadding: 0,
            expandedLengthMultiplier: 2,
            expandedDepthMultiplier: 1.4
        )
        let bottomDock = DockGeometry(
            edge: .bottom,
            frame: CGRect(x: 100, y: 0, width: 300, height: 80),
            thickness: 80,
            screenFrame: CGRect(x: 0, y: 0, width: 600, height: 400),
            isEstimated: false
        )
        let sideDock = DockGeometry(
            edge: .left,
            frame: CGRect(x: 0, y: 100, width: 80, height: 300),
            thickness: 80,
            screenFrame: CGRect(x: 0, y: 0, width: 600, height: 600),
            isEstimated: false
        )

        let rightCompact = layout.contentFrame(
            dock: bottomDock,
            placement: .afterDock,
            presentation: .compact
        )
        let rightExpanded = layout.contentFrame(
            dock: bottomDock,
            placement: .afterDock,
            presentation: .expanded
        )
        assert(rightCompact.minX == 410 && rightCompact.minY == 6 && rightCompact.width == 80)
        assert(rightExpanded.minX == 410 && rightExpanded.width == 160)
        assert(abs(rightExpanded.height - 112) < 0.001)

        let leftExpanded = layout.contentFrame(
            dock: bottomDock,
            placement: .beforeDock,
            presentation: .expanded
        )
        assert(leftExpanded.maxX == 90)

        let upExpanded = layout.contentFrame(
            dock: sideDock,
            placement: .beforeDock,
            presentation: .expanded
        )
        let downExpanded = layout.contentFrame(
            dock: sideDock,
            placement: .afterDock,
            presentation: .expanded
        )
        assert(upExpanded.minX == 6 && upExpanded.minY == 410 && upExpanded.height == 160)
        assert(abs(upExpanded.width - 112) < 0.001)
        assert(downExpanded.maxY == 90 && downExpanded.height == 160)

        let rightDock = DockGeometry(
            edge: .right,
            frame: CGRect(x: 520, y: 100, width: 80, height: 300),
            thickness: 80,
            screenFrame: CGRect(x: 0, y: 0, width: 600, height: 600),
            isEstimated: false
        )
        let rightSideWidget = layout.contentFrame(
            dock: rightDock,
            placement: .beforeDock,
            presentation: .compact
        )
        assert(rightSideWidget.minX == 514)

        assert(layout.placement(
            for: CGRect(x: 100, y: 0, width: 20, height: 20),
            relativeTo: bottomDock,
            keeping: .afterDock
        ) == .beforeDock)
        assert(layout.placement(
            for: CGRect(x: 400, y: 0, width: 20, height: 20),
            relativeTo: bottomDock,
            keeping: .beforeDock
        ) == .afterDock)
        assert(layout.placement(
            for: CGRect(x: 240, y: 0, width: 20, height: 20),
            relativeTo: bottomDock,
            keeping: .beforeDock
        ) == .beforeDock)
        assert(layout.placement(
            for: CGRect(x: 0, y: 400, width: 20, height: 20),
            relativeTo: sideDock,
            keeping: .afterDock
        ) == .beforeDock)
        assert(layout.placement(
            for: CGRect(x: 0, y: 0, width: 20, height: 20),
            relativeTo: sideDock,
            keeping: .beforeDock
        ) == .afterDock)
    }
}
