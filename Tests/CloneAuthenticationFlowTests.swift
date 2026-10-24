import AppKit
import Foundation
import Network

@main
struct CloneAuthenticationFlowTests {
  @MainActor
  static func main() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let config = directory.appendingPathComponent("gitconfig")
    for key in ProcessInfo.processInfo.environment.keys where key.hasPrefix("GIT_CONFIG_") {
      unsetenv(key)
    }
    setenv("GIT_CONFIG_GLOBAL", config.path, 1)
    setenv("GIT_CONFIG_NOSYSTEM", "1", 1)
    setenv("HOME", directory.path, 1)
    setenv("XDG_CONFIG_HOME", directory.path, 1)
    for key in ["http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "all_proxy"]
    {
      unsetenv(key)
    }
    setenv("NO_PROXY", "127.0.0.1,localhost", 1)
    _ = try git(["config", "--global", "credential.helper", ""])
    _ = try git(["config", "--global", "credential.interactive", "false"])
    _ = try git(["config", "--global", "http.proxy", ""])

    let server = try NWListener(using: .tcp, on: .any)
    server.newConnectionHandler = { connection in
      connection.start(queue: .global())
      connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
        let request = String(decoding: data ?? Data(), as: UTF8.self)
        let response: String
        if request.contains("/forbidden/") {
          response = "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        } else {
          response =
            "HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"test\"\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        }
        connection.send(
          content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
      }
    }
    let port: UInt16 = await withCheckedContinuation { continuation in
      server.stateUpdateHandler = { state in
        if case .ready = state {
          server.stateUpdateHandler = nil
          continuation.resume(returning: server.port!.rawValue)
        } else if case .failed(let error) = state {
          preconditionFailure("Local HTTP fixture failed: \(error)")
        }
      }
      server.start(queue: .global())
    }
    defer { server.cancel() }
    let rewrite = "url.http://127.0.0.1:\(port)/.insteadOf"
    _ = try git(["config", "--global", rewrite, "https://example.invalid/"])
    let originalConfig = try Data(contentsOf: config)

    let model = AppModel()
    model.commitMessage = "Keep this draft"
    model.presentClone()
    let destination = directory.appendingPathComponent("clone")
    await model.cloneRepository(
      address: "https://example.invalid/repo.git", destinationPath: destination.path)
    precondition(model.cloneAuthenticationGuide != nil)
    precondition(model.cloneError != nil && model.showClone && !model.isWorking)
    precondition(model.repositoryPath == nil && model.commitMessage == "Keep this draft")
    precondition(!FileManager.default.fileExists(atPath: destination.path))
    let configAfterFailure = try Data(contentsOf: config)
    precondition(configAfterFailure == originalConfig)

    model.presentClone()
    precondition(model.cloneAuthenticationGuide == nil && model.cloneError == nil)
    await model.cloneRepository(
      address: "https://example.invalid/forbidden/repo.git", destinationPath: destination.path)
    precondition(model.cloneAuthenticationGuide == nil && model.cloneError != nil)
    precondition(!model.isWorking && model.showClone)

    await model.cloneRepository(
      address: "https://example.invalid/repo.git", destinationPath: destination.path)
    precondition(model.cloneAuthenticationGuide != nil)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let retained = destination.appendingPathComponent("keep.txt")
    try Data("retained".utf8).write(to: retained)
    await model.cloneRepository(
      address: "https://example.invalid/repo.git", destinationPath: destination.path)
    precondition(model.cloneAuthenticationGuide == nil && model.cloneError != nil)
    let retainedContents = try String(contentsOf: retained, encoding: .utf8)
    precondition(retainedContents == "retained")

    await model.cloneRepository(
      address: "https://example.invalid/repo.git",
      destinationPath: directory.appendingPathComponent("retry").path)
    precondition(model.cloneAuthenticationGuide != nil)
    let source = directory.appendingPathComponent("repo.git")
    _ = try git(["init", "--bare", source.path])
    _ = try git(["config", "--global", "--unset-all", rewrite])
    _ = try git([
      "config", "--global", "url.\(source.absoluteString).insteadOf",
      "https://example.invalid/repo.git",
    ])
    let retryDestination = directory.appendingPathComponent("retry")
    await model.cloneRepository(
      address: "https://example.invalid/repo.git", destinationPath: retryDestination.path)
    precondition(
      model.cloneAuthenticationGuide == nil && model.cloneError == nil,
      model.cloneError ?? "Unexpected authentication guide")
    precondition(!model.showClone && !model.isWorking)
    let openedPath = model.repositoryPath.map {
      URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path
    }
    precondition(openedPath == retryDestination.resolvingSymlinksInPath().standardizedFileURL.path)
    precondition(
      FileManager.default.fileExists(atPath: retryDestination.appendingPathComponent(".git").path))
    model.closeWindow()
    print(
      "PASS: HTTPS authentication failure, guide reset, 403 classification, draft preservation, retained destination safety, retry and automatic opening"
    )
  }

  private static func git(_ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: "/")
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
