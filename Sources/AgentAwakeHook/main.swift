import AgentAwakeCore
import Darwin
import Foundation

private func option(named name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name),
          CommandLine.arguments.indices.contains(index + 1)
    else {
        return nil
    }

    return CommandLine.arguments[index + 1]
}

guard let providerName = option(named: "--provider"),
      let provider = AgentKind(identifier: providerName)
else {
    exit(EXIT_SUCCESS)
}

let input = FileHandle.standardInput.readDataToEndOfFile()
let event = try? JSONDecoder().decode(AgentHookEvent.self, from: input)
let rootDirectory = option(named: "--store-root").map {
    URL(fileURLWithPath: $0, isDirectory: true)
}
let store = AgentHookActivityStore(
    rootDirectory: rootDirectory
        ?? AgentHookActivityStore.defaultRootDirectory()
)

_ = try? store.handle(provider: provider, input: input)

if provider == .codex, event?.hookEventName == "Stop" {
    let response = Data(#"{"continue":true}"#.utf8)
    FileHandle.standardOutput.write(response)
    FileHandle.standardOutput.write(Data([0x0A]))
}

exit(EXIT_SUCCESS)
