import Foundation

@main
struct CloneAuthenticationGuideTests {
    static func main() throws {
        let address = "https://example.invalid/owner/repository.git"
        let failure = "remote: Invalid username or password.\nfatal: Authentication failed"
        let guide = CloneAuthenticationGuide(address: address, failure: failure, gitPath: "/usr/bin/git")!
        precondition(guide.server == "https://example.invalid")
        precondition(guide.configureCommand.contains("credential.https://example.invalid.helper"))
        precondition(guide.configureCommand.contains("--replace-all"))
        precondition(guide.configureCommand.contains("osxkeychain"))
        precondition(guide.authenticateCommand.contains("-u GIT_ASKPASS -u SSH_ASKPASS"))
        precondition(guide.authenticateCommand.contains("GIT_TERMINAL_PROMPT=1"))
        precondition(guide.authenticateCommand.contains("-C /"))
        precondition(guide.authenticateCommand.contains("ls-remote -- '\(address)' HEAD"))
        precondition(!guide.authenticateCommand.contains("credential fill"))

        for message in ["could not read Username", "terminal prompts disabled", "HTTP Basic: Access denied", "The requested URL returned error: 401"] {
            precondition(CloneAuthenticationGuide.isAuthenticationFailure(message))
        }
        for message in ["SSL certificate problem", "Could not resolve host", "Permission denied (publickey)", "The requested URL returned error: 403", "destination path already exists"] {
            precondition(!CloneAuthenticationGuide.isAuthenticationFailure(message))
        }
        for invalid in [
            "git@example.invalid:owner/repository.git", "ssh://git@example.invalid/owner/repository.git",
            "http://example.invalid/owner/repository.git", "https://user:secret@example.invalid/repo.git",
            "https://user@example.invalid/repo.git", "https://example.invalid/repo.git?token=secret",
            "https://example.invalid/repo.git#secret", "https://example.invalid/",
        ] {
            precondition(CloneAuthenticationGuide(address: invalid, failure: failure, gitPath: "/usr/bin/git") == nil)
        }
        let portGuide = CloneAuthenticationGuide(
            address: "https://example.invalid:8443/owner/repo.git", failure: failure, gitPath: "/usr/bin/git"
        )!
        precondition(portGuide.server == "https://example.invalid:8443")

        try checkConfiguration(guide)
        try checkShellQuoting(failure: failure)
        print("PASS: authentication detection, HTTPS-only recovery, secret URL rejection, scoped/idempotent configuration, shell quoting")
    }

    private static func checkConfiguration(_ guide: CloneAuthenticationGuide) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("gitconfig").path
        let environment = ["PATH": "/usr/bin:/bin", "HOME": directory.path, "GIT_CONFIG_GLOBAL": config, "GIT_CONFIG_NOSYSTEM": "1"]
        let key = "credential.https://example.invalid.helper"
        _ = try run("/usr/bin/git", ["config", "--global", "credential.helper", "custom-inherited"], environment)
        _ = try run("/usr/bin/git", ["config", "--global", "credential.https://other.invalid.helper", "other-helper"], environment)
        _ = try run("/bin/zsh", ["-f", "-c", guide.configureCommand], environment)
        _ = try run("/bin/zsh", ["-f", "-c", guide.configureCommand], environment)
        let helpers = try run("/usr/bin/git", ["config", "--global", "--get-all", key], environment)
        precondition(helpers == "\nosxkeychain\n")
        let inherited = try run("/usr/bin/git", ["config", "--global", "--get", "credential.helper"], environment)
        precondition(inherited == "custom-inherited\n")
        let other = try run("/usr/bin/git", ["config", "--global", "--get", "credential.https://other.invalid.helper"], environment)
        precondition(other == "other-helper\n")
    }

    private static func checkShellQuoting(failure: String) throws {
        let address = "https://example.invalid/owner/repo'$(printf-injection).git"
        let guide = CloneAuthenticationGuide(address: address, failure: failure, gitPath: "/path with spaces/git'custom")!
        let command = guide.authenticateCommand
        let capture = "env() { printf '%s\\0' \"$@\"; }; " + command
        let output = try run("/bin/zsh", ["-f", "-c", capture], ["PATH": "/usr/bin:/bin"])
        let arguments = output.split(separator: "\0").map(String.init)
        precondition(arguments.contains("/path with spaces/git'custom"))
        precondition(arguments.contains(address))
        precondition(arguments.last == "HEAD")
    }

    private static func run(_ path: String, _ arguments: [String], _ environment: [String: String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0, String(decoding: errorData, as: UTF8.self))
        return String(decoding: data, as: UTF8.self)
    }
}
