import AgentAwakeCore
import AppKit
import SwiftUI

struct ProtectionModeSlider: View {
    let selection: ProtectionMode
    let onSelect: (ProtectionMode) -> Void

    private let thumbDiameter: CGFloat = 15
    private let trackHeight: CGFloat = 3
    private let controlHeight: CGFloat = 22

    var body: some View {
        GeometryReader { geometry in
            let width = max(thumbDiameter, geometry.size.width)
            let radius = thumbDiameter / 2
            let usableWidth = max(1, width - thumbDiameter)
            let progress = CGFloat(selection.rawValue) / 4
            let thumbCenterX = radius + progress * usableWidth

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color(nsColor: .separatorColor).opacity(0.9))
                    .frame(width: usableWidth, height: trackHeight)
                    .position(
                        x: radius + usableWidth / 2,
                        y: controlHeight / 2
                    )

                if selection.rawValue > 0 {
                    Capsule()
                        .fill(Color.primary.opacity(0.58))
                        .frame(
                            width: progress * usableWidth,
                            height: trackHeight
                        )
                        .position(
                            x: radius + progress * usableWidth / 2,
                            y: controlHeight / 2
                        )
                }

                ForEach(0...4, id: \.self) { rawValue in
                    let stopProgress = CGFloat(rawValue) / 4

                    Circle()
                        .fill(
                            rawValue <= selection.rawValue
                                ? Color.primary.opacity(0.72)
                                : Color.secondary.opacity(0.48)
                        )
                        .frame(width: 4, height: 4)
                        .position(
                            x: radius + stopProgress * usableWidth,
                            y: controlHeight / 2
                        )
                }

                Circle()
                    .fill(
                        selection.isOff
                            ? Color.secondary
                            : Color.primary
                    )
                    .frame(
                        width: thumbDiameter,
                        height: thumbDiameter
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                Color(nsColor: .windowBackgroundColor)
                                    .opacity(0.72),
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color: Color.black.opacity(0.2),
                        radius: 1.5,
                        y: 1
                    )
                    .position(
                        x: thumbCenterX,
                        y: controlHeight / 2
                    )
            }
            .frame(width: width, height: controlHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        selectMode(
                            at: value.location.x,
                            width: width
                        )
                    }
                    .onEnded { value in
                        selectMode(
                            at: value.location.x,
                            width: width
                        )
                    }
            )
        }
        .frame(height: controlHeight)
        .animation(
            .easeOut(duration: 0.12),
            value: selection.rawValue
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("防休眠模式")
        .accessibilityValue(selection.title)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                selectRawValue(selection.rawValue + 1)
            case .decrement:
                selectRawValue(selection.rawValue - 1)
            @unknown default:
                break
            }
        }
        .help("拖动圆形滑块选择防休眠模式")
    }

    private func selectMode(at xPosition: CGFloat, width: CGFloat) {
        let radius = thumbDiameter / 2
        let usableWidth = max(1, width - thumbDiameter)
        let clampedX = min(
            max(xPosition, radius),
            width - radius
        )
        let progress = (clampedX - radius) / usableWidth
        selectRawValue(Int((progress * 4).rounded()))
    }

    private func selectRawValue(_ rawValue: Int) {
        let clampedRawValue = min(max(rawValue, 0), 4)
        guard let mode = ProtectionMode(rawValue: clampedRawValue),
              mode != selection
        else {
            return
        }

        onSelect(mode)
    }
}
