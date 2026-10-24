import Darwin
import Foundation

enum GitClone {
  struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  struct Source: Equatable {
    let address: String
    let suggestedName: String
  }

  struct Reservation {
    let destination: URL
    let device: dev_t
    let inode: ino_t
  }

  static func reserve(_ destination: URL) throws -> Reservation {
    guard mkdir(destination.path, 0o755) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    var attributes = stat()
    guard lstat(destination.path, &attributes) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    return Reservation(
      destination: destination, device: attributes.st_dev, inode: attributes.st_ino)
  }

  static func removeIfEmpty(_ reservation: Reservation) {
    var attributes = stat()
    guard lstat(reservation.destination.path, &attributes) == 0,
      attributes.st_dev == reservation.device, attributes.st_ino == reservation.inode
    else { return }
    _ = rmdir(reservation.destination.path)
  }

  static func source(_ raw: String) throws -> Source {
    let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !address.isEmpty, !address.contains(where: { $0.isWhitespace || $0.isNewline }),
      !address.hasPrefix("-")
    else {
      throw Failure(
        message: L10n.text(
          "请输入有效的 HTTP、HTTPS 或 SSH 仓库地址。", "Enter a valid HTTP, HTTPS, or SSH repository address."))
    }
    let path: String
    if address.contains("://") {
      guard let components = URLComponents(string: address),
        let scheme = components.scheme?.lowercased(), ["http", "https", "ssh"].contains(scheme),
        let host = components.host, !host.isEmpty,
        components.password == nil, !components.path.isEmpty, components.path != "/"
      else {
        throw Failure(
          message: L10n.text(
            "仓库地址需使用 HTTP、HTTPS 或 SSH，且不能包含密码。",
            "Use an HTTP, HTTPS, or SSH repository address without an embedded password."))
      }
      path = components.path
    } else {
      let pattern = #"^(?:[A-Za-z0-9._~+-]+@)?(?:[A-Za-z0-9._-]+|\[[0-9A-Fa-f:]+\]):(.+)$"#
      let expression = try NSRegularExpression(pattern: pattern)
      let range = NSRange(address.startIndex..., in: address)
      guard let match = expression.firstMatch(in: address, range: range),
        let pathRange = Range(match.range(at: 1), in: address)
      else {
        throw Failure(
          message: L10n.text(
            "请输入有效的 SSH 地址，例如 git@host:owner/repo.git。",
            "Enter a valid SSH address, such as git@host:owner/repo.git."))
      }
      path = String(address[pathRange])
      guard !path.hasPrefix(":") else {
        throw Failure(
          message: L10n.text(
            "不支持 Git remote-helper 地址，请使用 HTTP、HTTPS 或 SSH。",
            "Git remote-helper addresses are not supported. Use HTTP, HTTPS, or SSH."))
      }
    }
    let component = (path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) as NSString)
      .lastPathComponent
    let name = component.hasSuffix(".git") ? String(component.dropLast(4)) : component
    let suggestedName =
      name.isEmpty || name == "." || name == ".." || name.contains("/") ? "repository" : name
    return Source(address: address, suggestedName: suggestedName)
  }

  static func destination(_ raw: String) throws -> URL {
    let path = (raw.trimmingCharacters(in: .whitespacesAndNewlines) as NSString)
      .expandingTildeInPath
    guard path.hasPrefix("/"), !path.contains("\0") else {
      throw Failure(message: L10n.text("请选择项目的完整本地保存路径。", "Choose a full local destination path."))
    }
    let destination = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    var directory: ObjCBool = false
    let parent = destination.deletingLastPathComponent()
    guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &directory),
      directory.boolValue,
      FileManager.default.isWritableFile(atPath: parent.path)
    else {
      throw Failure(
        message: L10n.text(
          "保存路径的父文件夹不存在或不可写。", "The destination's parent folder does not exist or is not writable.")
      )
    }
    let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
    guard attributes == nil else {
      throw Failure(
        message: L10n.text(
          "保存路径已存在，请选择一个新的项目文件夹。", "The destination already exists. Choose a new project folder."))
    }
    return destination
  }

  static func clone(address: String, destinationPath: String) async throws -> (
    destination: URL, output: GitOutput
  ) {
    let source = try source(address)
    let destination = try destination(destinationPath)
    try Task.checkCancellation()
    let reservation = try reserve(destination)
    let output = await GitClient.run(
      args: [
        "-c", "credential.interactive=false", "clone", "--progress", "--", source.address,
        destination.path,
      ],
      cwd: destination.deletingLastPathComponent(), timeout: 900,
      environmentOverrides: [
        "GIT_SSH_COMMAND": "/usr/bin/ssh -o BatchMode=yes",
        "GIT_SSH_VARIANT": "ssh",
        "SSH_ASKPASS_REQUIRE": "never",
        "GIT_ASKPASS": "/usr/bin/false",
      ]
    )
    if output.exitCode != 0 { removeIfEmpty(reservation) }
    return (destination, output)
  }
}
