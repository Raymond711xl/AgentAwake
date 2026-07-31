import AgentAwakeCore
import AppKit
import SwiftUI

struct ProtectionModeSlider: View {
    let selection: ProtectionMode
    let onSelect: (ProtectionMode) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isDragging = false

    private let thumbDiameter: CGFloat = 19
    private let trackHeight: CGFloat = 5
    private let stopDiameter: CGFloat = 5
    private let controlHeight: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            let width = max(thumbDiameter, geometry.size.width)
            let radius = thumbDiameter / 2
            let usableWidth = max(1, width - thumbDiameter)
            let progress = CGFloat(selection.rawValue) / 4
            let thumbCenterX = radius + progress * usableWidth
            let centerY = controlHeight / 2

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(
                        Color.accentColor.opacity(
                            isHovering || isDragging ? 0.075 : 0
                        )
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                Color.accentColor.opacity(
                                    isHovering || isDragging ? 0.16 : 0
                                ),
                                lineWidth: 1
                            )
                    }
                    .frame(width: width, height: controlHeight - 2)
                    .position(x: width / 2, y: centerY)

                Capsule()
                    .fill(
                        Color(nsColor: .separatorColor).opacity(
                            isHovering || isDragging ? 1 : 0.82
                        )
                    )
                    .frame(width: usableWidth, height: trackHeight)
                    .position(
                        x: radius + usableWidth / 2,
                        y: centerY
                    )

                if selection.rawValue > 0 {
                    Capsule()
                        .fill(
                            Color.accentColor.opacity(
                                isHovering || isDragging ? 0.94 : 0.76
                            )
                        )
                        .frame(
                            width: progress * usableWidth,
                            height: trackHeight
                        )
                        .position(
                            x: radius + progress * usableWidth / 2,
                            y: centerY
                        )
                }

                ForEach(0...4, id: \.self) { rawValue in
                    let stopProgress = CGFloat(rawValue) / 4

                    Circle()
                        .fill(
                            rawValue <= selection.rawValue
                                ? Color.accentColor.opacity(0.95)
                                : Color.secondary.opacity(0.52)
                        )
                        .frame(
                            width: stopDiameter,
                            height: stopDiameter
                        )
                        .position(
                            x: radius + stopProgress * usableWidth,
                            y: centerY
                        )
                }

                Circle()
                    .fill(
                        selection.isOff
                            ? Color.secondary
                            : Color.accentColor
                    )
                    .frame(
                        width: thumbDiameter,
                        height: thumbDiameter
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                Color(nsColor: .windowBackgroundColor)
                                    .opacity(0.88),
                                lineWidth: 1.25
                            )
                    }
                    .overlay {
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 5, height: 5)
                    }
                    .shadow(
                        color: Color.accentColor.opacity(
                            isDragging ? 0.5 : isHovering ? 0.34 : 0.1
                        ),
                        radius: isDragging ? 7 : isHovering ? 5 : 2
                    )
                    .shadow(
                        color: Color.black.opacity(0.22),
                        radius: 2,
                        y: 1
                    )
                    .scaleEffect(
                        isDragging ? 1.12 : isHovering ? 1.07 : 1
                    )
                    .position(
                        x: thumbCenterX,
                        y: centerY
                    )
            }
            .frame(width: width, height: controlHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            withAnimation(hoverAnimation) {
                                isDragging = true
                            }
                        }
                        selectMode(
                            at: value.location.x,
                            width: width,
                            givesFeedback: true
                        )
                    }
                    .onEnded { value in
                        selectMode(
                            at: value.location.x,
                            width: width,
                            givesFeedback: true
                        )
                        withAnimation(snapAnimation) {
                            isDragging = false
                        }
                    }
            )
            .onHover { hovering in
                withAnimation(hoverAnimation) {
                    isHovering = hovering
                }
            }
        }
        .frame(height: controlHeight)
        .animation(
            snapAnimation,
            value: selection.rawValue
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("防休眠模式")
        .accessibilityValue(selection.title)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                selectRawValue(
                    selection.rawValue + 1,
                    givesFeedback: false
                )
            case .decrement:
                selectRawValue(
                    selection.rawValue - 1,
                    givesFeedback: false
                )
            @unknown default:
                break
            }
        }
        .help("拖动圆形滑块选择防休眠模式")
    }

    private var hoverAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.16)
    }

    private var snapAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : .interactiveSpring(
                response: 0.24,
                dampingFraction: 0.7,
                blendDuration: 0.08
            )
    }

    private func selectMode(
        at xPosition: CGFloat,
        width: CGFloat,
        givesFeedback: Bool
    ) {
        let radius = thumbDiameter / 2
        let usableWidth = max(1, width - thumbDiameter)
        let clampedX = min(
            max(xPosition, radius),
            width - radius
        )
        let progress = (clampedX - radius) / usableWidth
        selectRawValue(
            Int((progress * 4).rounded()),
            givesFeedback: givesFeedback
        )
    }

    private func selectRawValue(
        _ rawValue: Int,
        givesFeedback: Bool
    ) {
        let clampedRawValue = min(max(rawValue, 0), 4)
        guard let mode = ProtectionMode(rawValue: clampedRawValue),
              mode != selection
        else {
            return
        }

        if givesFeedback && !reduceMotion {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment,
                performanceTime: .now
            )
        }

        withAnimation(snapAnimation) {
            onSelect(mode)
        }
    }
}
