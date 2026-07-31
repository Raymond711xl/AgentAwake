import AppKit
import SwiftUI

enum SleepStatusIcon {
    static let menuBarSize = NSSize(width: 27, height: 18)

    static func makeImage(
        color: NSColor,
        accessibilityDescription: String
    ) -> NSImage {
        let size = menuBarSize
        let image = NSImage(
            size: size,
            flipped: true
        ) { _ in
            let pointConfiguration = NSImage.SymbolConfiguration(
                pointSize: 12,
                weight: .medium
            )
            let paletteConfiguration = NSImage.SymbolConfiguration(
                paletteColors: [color]
            )
            let symbolConfiguration = pointConfiguration.applying(
                paletteConfiguration
            )

            if let sparkle = NSImage(
                systemSymbolName: "sparkle",
                accessibilityDescription: nil
            )?.withSymbolConfiguration(symbolConfiguration) {
                sparkle.draw(
                    in: NSRect(x: 0, y: 3, width: 13, height: 13),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: nil
                )
            }

            let zPositions: [
                (point: NSPoint, size: CGFloat)
            ] = [
                (NSPoint(x: 12.5, y: 9.5), 5.5),
                (NSPoint(x: 17, y: 5), 6.5),
                (NSPoint(x: 22, y: 0), 7.5)
            ]

            for position in zPositions {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(
                        ofSize: position.size,
                        weight: .semibold
                    ),
                    .foregroundColor: color
                ]
                ("Z" as NSString).draw(
                    at: position.point,
                    withAttributes: attributes
                )
            }

            return true
        }

        image.isTemplate = false
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}

struct SleepStatusMark: View {
    let isActive: Bool

    private var markColor: Color {
        isActive ? .primary : .secondary
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: "sparkle")
                .font(.system(size: 20, weight: .medium))
                .offset(x: 0, y: 5)

            Text("Z")
                .font(.system(size: 6, weight: .semibold))
                .offset(x: 17, y: 14)

            Text("Z")
                .font(.system(size: 7, weight: .semibold))
                .offset(x: 23, y: 8)

            Text("Z")
                .font(.system(size: 8, weight: .semibold))
                .offset(x: 30, y: 1)
        }
        .foregroundStyle(markColor)
        .frame(width: 39, height: 28, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("睡眠星标")
    }
}
