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
            let surfaceSize = CGSize(
                width: innerSize.width / DockMetrics.maximumSurfaceScale,
                height: innerSize.height / DockMetrics.maximumSurfaceScale
            )
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
                alignment: origin.alignment
            )
            .padding(shadowPadding)
        }
        .ignoresSafeArea()
    }
}

private struct WidgetSurfaceView: View {
    private static let dragThreshold: CGFloat = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPanelDragging = false

    let state: WidgetPanelState
    let origin: WidgetCorner
    let onInteraction: (WidgetInteraction) -> Void

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let cornerRadius = state.presentation == .expanded ? 42 : side * 0.3
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            WidgetMaterialView()
                .containerShape(shape)
                .clipShape(shape)
                .overlay {
                    shape
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .scaleEffect(
                    reduceMotion || state.presentation != .expanded ? 1 : 1.05,
                    anchor: origin.unitPoint
                )
                .animation(.easeOut(duration: 0.15), value: state.presentation)
                .gesture(panelDragGesture)
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active:
                        onInteraction(.hoverChanged(true))
                    case .ended:
                        onInteraction(.hoverChanged(false))
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

private struct WidgetMaterialView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.alphaValue = 0.55
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
