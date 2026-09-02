import AppKit
import SwiftUI

enum WidgetInteraction {
    case hoverChanged(Bool)
    case dragStarted
    case dragChanged
    case dragEnded
}

struct WidgetContentView: View {
    let state: WidgetPanelState
    let shadowPadding: CGFloat
    let onInteraction: (WidgetInteraction) -> Void

    var body: some View {
        GeometryReader { proxy in
            let innerSize = CGSize(
                width: max(0, proxy.size.width - shadowPadding * 2),
                height: max(0, proxy.size.height - shadowPadding * 2)
            )
            let fittedSurfaceSize = CGSize(
                width: innerSize.width / DockMetrics.maximumSurfaceScale,
                height: innerSize.height / DockMetrics.maximumSurfaceScale
            )
            let surfaceSize = state.repositioningSurfaceSize ?? fittedSurfaceSize
            let origin = state.placement.originCorner(for: state.dockEdge)

            WidgetSurfaceView(
                state: state,
                origin: origin,
                onInteraction: onInteraction
            )
            .frame(width: surfaceSize.width, height: surfaceSize.height)
            .frame(
                width: innerSize.width,
                height: innerSize.height,
                alignment: state.movement == .repositioning ? .center : origin.alignment
            )
            .padding(shadowPadding)
        }
        .ignoresSafeArea()
    }
}

private struct WidgetSurfaceView: View {
    private static let dragThreshold: CGFloat = 4
    fileprivate static let handleInset: CGFloat = 32

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPanelDragging = false
    @State private var isHandleHovered = false

    let state: WidgetPanelState
    let origin: WidgetCorner
    let onInteraction: (WidgetInteraction) -> Void

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let cornerRadius = state.presentation == .expanded ? 42 : side * 0.3
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            let direction = state.placement.expansionDirection(for: state.dockEdge)
            let surfaceScale = reduceMotion || state.presentation != .expanded
                ? 1
                : isHandleHovered
                    ? DockMetrics.maximumSurfaceScale
                    : DockMetrics.expandedSurfaceScale

            ZStack {
                WidgetMaterialView()
                Color(nsColor: .controlBackgroundColor)
                    .opacity(0.16)
                    .allowsHitTesting(false)
                #if DEBUG
                WidgetContentProbe(
                    presentation: state.presentation,
                    origin: origin
                )
                #endif
            }
                .containerShape(shape)
                .clipShape(shape)
                .overlay {
                    shape
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .scaleEffect(surfaceScale, anchor: origin.unitPoint)
                .animation(.easeOut(duration: 0.15), value: state.presentation)
                .animation(.easeOut(duration: 0.15), value: isHandleHovered)
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active:
                        onInteraction(.hoverChanged(true))
                    case .ended:
                        onInteraction(.hoverChanged(false))
                    }
                }
                .overlay(alignment: direction.handleAlignment) {
                    WidgetDragHandleView(
                        direction: direction,
                        isHovered: isHandleHovered
                    )
                    .frame(
                        width: direction.handleSize.width,
                        height: direction.handleSize.height
                    )
                    .offset(direction.handleOffset(in: proxy.size, scale: surfaceScale))
                    .opacity(state.presentation == .expanded ? 1 : 0)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.15), value: state.presentation)
                    .animation(.easeOut(duration: 0.15), value: surfaceScale)
                }
                .overlay(alignment: direction.handleAlignment) {
                    Color.clear
                    .frame(
                        width: direction.handleHitSize(in: proxy.size).width,
                        height: direction.handleHitSize(in: proxy.size).height
                    )
                    .contentShape(Rectangle())
                    .pointerStyle(isPanelDragging ? .grabActive : .grabIdle)
                    .offset(
                        direction.handleOffset(
                            in: proxy.size,
                            scale: DockMetrics.maximumSurfaceScale
                        )
                    )
                    .allowsHitTesting(
                        state.presentation == .expanded || state.movement == .repositioning
                    )
                    .gesture(panelDragGesture)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active:
                            isHandleHovered = true
                            onInteraction(.hoverChanged(true))
                        case .ended:
                            isHandleHovered = false
                            onInteraction(.hoverChanged(false))
                        }
                    }
                    .accessibilityLabel("위젯 이동")
                }
                .onChange(of: state.presentation) { _, presentation in
                    if presentation == .compact {
                        isHandleHovered = false
                    }
                }
        }
    }

    private var panelDragGesture: some Gesture {
        DragGesture(minimumDistance: Self.dragThreshold, coordinateSpace: .global)
            .onChanged { value in
                if !isPanelDragging {
                    isPanelDragging = true
                    onInteraction(.dragStarted)
                }
                onInteraction(.dragChanged)
            }
            .onEnded { _ in
                guard isPanelDragging else { return }
                isPanelDragging = false
                onInteraction(.dragEnded)
            }
    }
}

#if DEBUG
private struct WidgetContentProbe: View {
    let presentation: WidgetPresentation
    let origin: WidgetCorner

    var body: some View {
        GeometryReader { proxy in
            let originOffset = CGSize(
                width: (origin.isLeft ? -1 : 1) * proxy.size.width / 2,
                height: (origin.isTop ? -1 : 1) * proxy.size.height / 2
            )

            ZStack {
                switch presentation {
                case .compact:
                    label("COMPACT", from: originOffset)
                case .expanded:
                    label("EXPANDED", from: originOffset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: origin.alignment) {
                Circle()
                    .fill(.pink)
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1)
                    }
                    .frame(width: 8, height: 8)
                    .padding(10)
            }
        }
        .animation(.spring(duration: 0.2, bounce: 0.2), value: presentation)
        .allowsHitTesting(false)
    }

    private func label(_ text: String, from originOffset: CGSize) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.8))
            .transition(
                .offset(x: originOffset.width, y: originOffset.height)
                    .combined(with: .scale(scale: 0.7, anchor: origin.unitPoint))
                    .combined(with: .opacity)
            )
    }
}
#endif

private struct WidgetDragHandleView: View {
    let direction: WidgetExpansionDirection
    let isHovered: Bool

    var body: some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(.white.opacity(isHovered ? 0.8 : 0.2))
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                }
                .frame(
                    width: direction.indicatorSize.width,
                    height: direction.indicatorSize.height
                )
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

private struct WidgetMaterialView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.alphaValue = 1
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private extension WidgetCorner {
    var alignment: Alignment {
        switch self {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }

    var unitPoint: UnitPoint {
        switch self {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }
}

private extension WidgetExpansionDirection {
    var handleAlignment: Alignment {
        switch self {
        case .up: .top
        case .down: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    var handleSize: CGSize {
        switch self {
        case .up, .down: CGSize(width: 120, height: 44)
        case .left, .right: CGSize(width: 44, height: 120)
        }
    }

    var indicatorSize: CGSize {
        switch self {
        case .up, .down: CGSize(width: 50, height: 6)
        case .left, .right: CGSize(width: 6, height: 50)
        }
    }

    func handleHitSize(in size: CGSize) -> CGSize {
        let scaleTravel = DockMetrics.maximumSurfaceScale - DockMetrics.expandedSurfaceScale

        return switch self {
        case .up, .down:
            CGSize(width: handleSize.width, height: handleSize.height + size.height * scaleTravel)
        case .left, .right:
            CGSize(width: handleSize.width + size.width * scaleTravel, height: handleSize.height)
        }
    }

    func handleOffset(in size: CGSize, scale: CGFloat) -> CGSize {
        let overflow = CGSize(
            width: size.width * (scale - 1),
            height: size.height * (scale - 1)
        )

        return switch self {
        case .up:
            CGSize(width: 0, height: -WidgetSurfaceView.handleInset - overflow.height)
        case .down:
            CGSize(width: 0, height: WidgetSurfaceView.handleInset + overflow.height)
        case .left:
            CGSize(width: -WidgetSurfaceView.handleInset - overflow.width, height: 0)
        case .right:
            CGSize(width: WidgetSurfaceView.handleInset + overflow.width, height: 0)
        }
    }
}
