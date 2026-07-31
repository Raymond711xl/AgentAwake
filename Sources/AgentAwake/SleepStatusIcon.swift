import AppKit
import SwiftUI

enum SleepStatusIcon {
    static let menuBarSize = NSSize(width: 18, height: 18)

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
                    in: NSRect(x: 0, y: 4, width: 13, height: 13),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: nil
                )
            }

            let zAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 7.5, weight: .medium),
                .foregroundColor: color
            ]
            if let context = NSGraphicsContext.current {
                context.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.translateX(by: 10.25, yBy: 0.75)
                transform.rotate(byDegrees: -8)
                transform.concat()
                ("Z" as NSString).draw(
                    at: .zero,
                    withAttributes: zAttributes
                )
                context.restoreGraphicsState()
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
        isActive
            ? Color(red: 0.85, green: 0.47, blue: 0.34)
            : .secondary
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: "sparkle")
                .font(.system(size: 20, weight: .medium))
                .offset(x: 0, y: 5)

            Text("Z")
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .rotationEffect(.degrees(-8))
                .offset(x: 15, y: 0)
        }
        .foregroundStyle(markColor)
        .frame(width: 28, height: 28, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("睡眠十字星与 Z 标记")
    }
}
