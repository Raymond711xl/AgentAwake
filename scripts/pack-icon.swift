import Foundation

private struct IconEntry {
    let type: String
    let filename: String
}

private enum PackError: LocalizedError {
    case usage
    case missingFile(String)
    case invalidType(String)
    case fileTooLarge(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "usage: pack-icon.swift <AppIcon.iconset> <AppIcon.icns>"
        case let .missingFile(path):
            return "missing icon file: \(path)"
        case let .invalidType(type):
            return "ICNS entry type must contain four ASCII bytes: \(type)"
        case let .fileTooLarge(path):
            return "icon file is too large for ICNS: \(path)"
        }
    }
}

private let entries = [
    IconEntry(type: "icp4", filename: "icon_16x16.png"),
    IconEntry(type: "ic11", filename: "icon_16x16@2x.png"),
    IconEntry(type: "icp5", filename: "icon_32x32.png"),
    IconEntry(type: "ic12", filename: "icon_32x32@2x.png"),
    IconEntry(type: "ic07", filename: "icon_128x128.png"),
    IconEntry(type: "ic13", filename: "icon_128x128@2x.png"),
    IconEntry(type: "ic08", filename: "icon_256x256.png"),
    IconEntry(type: "ic14", filename: "icon_256x256@2x.png"),
    IconEntry(type: "ic09", filename: "icon_512x512.png"),
    IconEntry(type: "ic10", filename: "icon_512x512@2x.png")
]

private func bigEndianData(_ value: UInt32) -> Data {
    var bigEndianValue = value.bigEndian
    return withUnsafeBytes(of: &bigEndianValue) { Data($0) }
}

private func checkedLength(
    payloadCount: Int,
    path: String
) throws -> UInt32 {
    let (length, overflow) = payloadCount.addingReportingOverflow(8)
    guard !overflow, length <= Int(UInt32.max) else {
        throw PackError.fileTooLarge(path)
    }
    return UInt32(length)
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw PackError.usage
    }

    let iconsetURL = URL(
        fileURLWithPath: CommandLine.arguments[1],
        isDirectory: true
    )
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
    var body = Data()

    for entry in entries {
        let fileURL = iconsetURL.appendingPathComponent(entry.filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw PackError.missingFile(fileURL.path)
        }

        guard let typeData = entry.type.data(using: .ascii),
              typeData.count == 4
        else {
            throw PackError.invalidType(entry.type)
        }

        let imageData = try Data(contentsOf: fileURL)
        body.append(typeData)
        body.append(
            bigEndianData(
                try checkedLength(
                    payloadCount: imageData.count,
                    path: fileURL.path
                )
            )
        )
        body.append(imageData)
    }

    let totalLength = try checkedLength(
        payloadCount: body.count,
        path: outputURL.path
    )
    var iconData = Data("icns".utf8)
    iconData.append(bigEndianData(totalLength))
    iconData.append(body)
    try iconData.write(to: outputURL, options: .atomic)
} catch {
    fputs("AgentAwake icon packer: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
