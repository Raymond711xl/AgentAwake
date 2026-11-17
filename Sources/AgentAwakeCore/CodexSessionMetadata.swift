import Foundation

enum CodexSessionMetadata {
    static let maximumHeaderBytes = 65_536

    private struct Header: Decodable {
        struct Payload: Decodable {
            let originator: String?
        }

        let type: String
        let payload: Payload
    }

    // ChatGPT Work and Codex share a rollout directory and Hook provider.
    // Read only the first record and keep only the surface identifier.
    static func surface(from handle: FileHandle) -> AgentSurface? {
        guard (try? handle.seek(toOffset: 0)) != nil else { return nil }
        guard let bytes = try? handle.read(upToCount: maximumHeaderBytes),
              let newline = bytes.firstIndex(of: 0x0A),
              let header = try? JSONDecoder().decode(
                  Header.self, from: Data(bytes[..<newline])
              ),
              header.type == "session_meta",
              header.payload.originator == "codex_work_desktop"
        else {
            return nil
        }
        return .chatGPTWork
    }
}
