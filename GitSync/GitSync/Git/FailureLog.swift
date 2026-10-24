import Foundation

enum FailureLog {
  static func make(outputs: [GitOutput]) -> LocalizedText {
    let logs = outputs.map { output in
      LocalizedText(
        """
        $ \(output.commandLine)
        退出码：\(output.exitCode)
        --- 标准输出 ---
        \(output.stdoutText.isEmpty ? "（空）" : output.stdoutText)
        --- 标准错误 ---
        \(output.stderrText.isEmpty ? "（空）" : output.stderrText)
        """,
        """
        $ \(output.commandLine)
        Exit code: \(output.exitCode)
        --- stdout ---
        \(output.stdoutText.isEmpty ? "(empty)" : output.stdoutText)
        --- stderr ---
        \(output.stderrText.isEmpty ? "(empty)" : output.stderrText)
        """
      )
    }
    return truncate(
      LocalizedText(
        logs.map(\.chinese).joined(separator: "\n"),
        logs.map(\.english).joined(separator: "\n")
      ))
  }

  static func truncate(_ text: LocalizedText) -> LocalizedText {
    LocalizedText(
      truncate(text.chinese, notice: "日志过长，仅显示末尾 2000 行。"),
      truncate(text.english, notice: "Log too long; showing only the last 2000 lines.")
    )
  }

  private static func truncate(_ text: String, notice: String) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count > 2000 else { return text }
    let tail = lines.suffix(2000).joined(separator: "\n")
    return "\(notice)\n\n\(tail)"
  }

  static func reason(action: LocalizedText, outputs: [GitOutput], conflict: Bool) -> LocalizedText {
    if conflict {
      if action.chinese == "拉取" { return L10n.message("拉取产生冲突。", "Pull resulted in conflicts.") }
      return L10n.message(
        "合并产生冲突，解决后提交以完成合并。",
        "Merge resulted in conflicts. Resolve them and commit to complete the merge.")
    }
    let combined = outputs.map { $0.stdoutText + "\n" + $0.stderrText }.joined(separator: "\n")
    let lower = combined.lowercased()
    if outputs.contains(where: { $0.exitCode == 124 }) {
      return L10n.message(
        "Git 命令执行超时，已自动终止。", "The Git command timed out and was terminated automatically.")
    }
    if outputs.contains(where: { $0.exitCode == -1 && $0.stderrText.contains("未找到 git") }) {
      return L10n.message("未找到 git。", "Git was not found.")
    }
    if lower.contains("index.lock") || lower.contains("unable to create") && lower.contains(".lock")
    {
      return L10n.message("仓库被锁定，请稍后重试。", "The repository is locked. Try again later.")
    }
    if lower.contains("authentication failed")
      || lower.contains("permission denied (publickey)")
      || lower.contains("could not read from remote")
      || lower.contains("terminal prompts disabled")
      || lower.contains("could not read username")
    {
      return L10n.message(
        "需要登录。请使用系统已配置的 SSH 或 credential helper。",
        "Authentication is required. Use SSH or a credential helper configured on your system.")
    }
    if lower.contains("non-fast-forward")
      || lower.contains("failed to push some refs")
      || lower.contains("updates were rejected")
    {
      return L10n.message("远程拒绝推送。", "The remote rejected the push.")
    }
    if lower.contains("no tracking information") || lower.contains("no upstream") {
      return L10n.message(
        "当前分支没有上游。请先推送，或为该分支设置上游。",
        "The current branch has no upstream. Push first or configure an upstream for this branch.")
    }
    if lower.contains("does not appear to be a git repository")
      || lower.contains("no configured push destination")
      || lower.contains("no such remote")
    {
      if action.chinese == "推送" {
        return L10n.message("无法推送：没有名为 origin 的远程。", "Cannot push: no remote named origin.")
      }
      return L10n.message("该仓库没有远程。", "This repository has no remotes.")
    }
    if lower.contains("conflict") || lower.contains("fix conflicts") {
      if action.chinese == "拉取" { return L10n.message("拉取产生冲突。", "Pull resulted in conflicts.") }
      if action.chinese == "合并" {
        return L10n.message(
          "合并产生冲突，解决后提交以完成合并。",
          "Merge resulted in conflicts. Resolve them and commit to complete the merge.")
      }
    }
    return L10n.message("Git 命令执行失败。", "The Git command failed.")
  }
}
