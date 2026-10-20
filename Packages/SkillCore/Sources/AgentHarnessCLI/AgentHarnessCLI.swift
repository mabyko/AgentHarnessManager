import Foundation
import SkillCore

enum CLIError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { message } else { nil } }
}

@main @MainActor
struct AgentHarnessCLI {
    static func main() async {
        do { try await run() }
        catch {
            let data = (try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription])) ?? Data("{\"error\":\"Command failed\"}".utf8)
            try? FileHandle.standardError.write(contentsOf: data + Data([10]))
            exit(1)
        }
    }

    private static func run() async throws {
        var args = Array(CommandLine.arguments.dropFirst())
        var home = FileManager.default.homeDirectoryForCurrentUser
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let app = Bundle(url: executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        var domain = app?.bundleIdentifier ?? ManagementConfiguration.releaseDomain
        while args.first == "--home" || args.first == "--domain" {
            guard args.count >= 2 else { throw CLIError.message("Missing global option value") }
            let option = args.removeFirst(), value = args.removeFirst()
            if option == "--home" {
                guard value.hasPrefix("/") else { throw CLIError.message("--home must be an absolute path") }
                home = URL(fileURLWithPath: value)
            } else { domain = value }
        }
        let command = args.isEmpty ? "help" : args.removeFirst()
        if ["help", "--help", "-h"].contains(command) {
            print("""
            Agent Harness Manager CLI
            ahm [--home /absolute/path] [--domain bundle.id] <command>
              status | groups | check | requests
              list [--query text] [--agent codex|claudeCode|grokBuild|antigravity|opencode|pi|devin|cursor|custom] [--offset N] [--limit N]
              show <installation-id>
              plan enable|disable <installation-id>...
              request enable|disable <installation-id>...
              mcp    Newline-delimited JSON-RPC over stdio
            All ordinary output is JSON. Requests require review and approval in the app.
            No ChatGPT login, Keychain access, LLM invocation, or arbitrary shell execution.
            """)
            return
        }
        let commands = ManagementCommands(home: home, domain: domain)
        if command == "mcp" {
            guard args.isEmpty else { throw CLIError.message("Unexpected MCP argument") }
            var server = MCPServer(commands: commands); try await server.serve(); return
        }
        var arguments: [String: Any] = [:]
        if command == "list" {
            while !args.isEmpty {
                guard args.count >= 2 else { throw CLIError.message("Missing list option value") }
                let option = args.removeFirst(), value = args.removeFirst()
                switch option {
                case "--query": arguments["query"] = value
                case "--agent": arguments["agent"] = value
                case "--offset", "--limit":
                    guard let number = Int(value) else { throw CLIError.message("Expected integer") }
                    arguments[String(option.dropFirst(2))] = number
                default: throw CLIError.message("Unknown list option")
                }
            }
        } else if command == "show" {
            guard args.count == 1 else { throw CLIError.message("Expected one installation ID") }
            arguments["installationID"] = args.removeFirst()
        } else if command == "plan" || command == "request" {
            guard let operation = args.first, ["enable", "disable"].contains(operation), args.count >= 2 else {
                throw CLIError.message("Expected enable|disable and installation IDs")
            }
            arguments["enabled"] = args.removeFirst() == "enable"; arguments["installationIDs"] = args; args = []
        }
        guard args.isEmpty else { throw CLIError.message("Unexpected command argument") }
        let result = try await commands.run(command, arguments: arguments)
        var bytes = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        bytes.append(10); try FileHandle.standardOutput.write(contentsOf: bytes)
    }
}
