import Foundation

@main
struct GitHookEnvironmentTests {
  @MainActor
  static func main() async {
    setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin", 1)
    let output = await GitClient.run(
      args: ["-c", "alias.hook-environment=!command -v ci-script", "hook-environment"],
      cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    )
    precondition(output.exitCode == 0, output.stderrText)
    let toolPath = output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    precondition(FileManager.default.isExecutableFile(atPath: toolPath))
    print("PASS: Git subprocess resolves ci-script with a minimal GUI-style PATH: \(toolPath)")
  }
}