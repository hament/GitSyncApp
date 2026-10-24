import AppKit
import SwiftUI

struct CloneAuthenticationView: View {
  let guide: CloneAuthenticationGuide
  let canRetry: Bool
  var retry: () -> Void

  @State private var step = Step.configure
  @State private var copied = false
  @State private var terminalFailed = false

  private enum Step: Int, CaseIterable {
    case configure
    case authenticate
    case retry

    var title: String {
      switch self {
      case .configure: L10n.text("钥匙串", "Keychain")
      case .authenticate: L10n.text("终端认证", "Authenticate")
      case .retry: L10n.text("重试克隆", "Retry Clone")
      }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Divider()
      Label(L10n.text("需要 HTTPS 认证", "HTTPS Authentication Required"), systemImage: "key")
        .font(.headline)
      Text(guide.server)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
        .help(guide.server)
      HStack(spacing: 8) {
        ForEach(Step.allCases, id: \.rawValue) { item in
          if item != .configure {
            Image(systemName: "chevron.right")
              .foregroundStyle(.tertiary)
          }
          Label(
            item.title,
            systemImage: item.rawValue < step.rawValue
              ? "checkmark.circle.fill" : "\(item.rawValue + 1).circle"
          )
          .foregroundStyle(item == step ? Color.accentColor : Color.secondary)
        }
      }
      .font(.caption)
      .accessibilityIdentifier("clone.auth.steps")

      Text(instructions)
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)

      if let command {
        HStack {
          Text(L10n.text("终端命令", "Terminal Command"))
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Button(action: openTerminal) {
            Image(systemName: "terminal")
          }
          .help(L10n.text("打开终端", "Open Terminal"))
          .accessibilityLabel(L10n.text("打开终端", "Open Terminal"))
          .accessibilityIdentifier("clone.auth.terminal")
          Button {
            NSPasteboard.general.clearContents()
            copied = NSPasteboard.general.setString(command, forType: .string)
          } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
          }
          .help(copied ? L10n.text("已复制命令", "Command Copied") : L10n.text("复制命令", "Copy Command"))
          .accessibilityLabel(L10n.text("复制命令", "Copy Command"))
          .accessibilityValue(copied ? L10n.text("已复制", "Copied") : "")
          .accessibilityIdentifier("clone.auth.copy.\(step.rawValue)")
        }
        ScrollView(.horizontal) {
          Text(command)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: true, vertical: true)
            .padding(8)
        }
        .frame(height: step == .configure ? 64 : 48)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
      }
      if terminalFailed {
        Text(
          L10n.text(
            "无法打开终端，请从“应用程序 / 实用工具”手动打开。",
            "Could not open Terminal. Open it from Applications / Utilities.")
        )
        .font(.caption)
        .foregroundStyle(.red)
      }
      if step == .authenticate {
        Text(
          L10n.text(
            "仅在终端输入用户名及公司允许的 Token / HTTPS 凭据。密码输入时不显示字符。成功后凭据会保存到钥匙串；不要粘贴到 App。若公司使用 SSO，请先完成所需授权。",
            "Enter your username and company-approved token / HTTPS credential only in Terminal. Password input is hidden. Successful authentication saves the credential to Keychain; do not paste it into this app. Complete any required company SSO authorization."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        if step != .configure {
          Button {
            step = Step(rawValue: step.rawValue - 1) ?? .configure
          } label: {
            Image(systemName: "arrow.left")
          }
          .help(L10n.text("上一步", "Previous Step"))
          .accessibilityLabel(L10n.text("上一步", "Previous Step"))
          .accessibilityIdentifier("clone.auth.back")
        }
        Spacer()
        if step == .retry {
          Button(action: retry) {
            Label(L10n.text("重试克隆", "Retry Clone"), systemImage: "arrow.clockwise")
          }
          .disabled(!canRetry)
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("clone.auth.retry")
        } else {
          Button {
            step = Step(rawValue: step.rawValue + 1) ?? .retry
          } label: {
            Label(
              step == .configure
                ? L10n.text("已执行，下一步", "Executed, Next")
                : L10n.text("认证成功，继续", "Authenticated, Continue"),
              systemImage: "arrow.right"
            )
          }
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("clone.auth.next")
        }
      }
    }
    .onChange(of: step) {
      copied = false
      terminalFailed = false
    }
  }

  private var command: String? {
    switch step {
    case .configure: guide.configureCommand
    case .authenticate: guide.authenticateCommand
    case .retry: nil
    }
  }

  private var instructions: String {
    switch step {
    case .configure:
      L10n.text(
        "复制命令并在本机终端执行。此命令仅将上述服务器的凭据工具替换为 macOS 钥匙串，不会更改其他服务器的配置，也不会把 Token 写入 Git 配置。",
        "Copy and execute the command in your local terminal. It replaces the credential helpers for this server with macOS Keychain, without changing other servers or writing tokens to Git configuration."
      )
    case .authenticate:
      L10n.text(
        "复制命令并在终端执行，完成一次远程访问认证。此操作只查询远程 HEAD，不会克隆或修改项目文件。若失败，请先确认凭据和仓库权限，再继续。",
        "Copy and execute the command in Terminal to authenticate a remote request. It only queries the remote HEAD; no project files are cloned or changed. If it fails, verify your credentials and repository access before continuing."
      )
    case .retry:
      L10n.text(
        "确认终端认证成功后，重试克隆。App 将通过 Git 从钥匙串获取凭据，不会读取终端中的密码输入。若上方提示保存路径已存在，请先选择新的项目文件夹；原目录不会被删除。",
        "After authentication succeeds in Terminal, retry cloning. Git will obtain credentials from Keychain; this app does not read terminal password input. If the destination above already exists, choose a new project folder first. Existing folders will not be deleted."
      )
    }
  }

  private func openTerminal() {
    terminalFailed = !NSWorkspace.shared.open(
      URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
  }
}
