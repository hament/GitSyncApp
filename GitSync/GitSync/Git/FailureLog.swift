import Foundation

enum FailureLog {
    static func make(outputs: [GitOutput]) -> String {
        let body = outputs.map { output in
            """
            $ \(output.commandLine)
            退出码: \(output.exitCode)
            --- 标准输出 ---
            \(output.stdoutText.isEmpty ? "（空）" : output.stdoutText)
            --- 标准错误 ---
            \(output.stderrText.isEmpty ? "（空）" : output.stderrText)
            """
        }.joined(separator: "\n")
        return truncate(body)
    }

    static func truncate(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 2000 else { return text }
        let tail = lines.suffix(2000).joined(separator: "\n")
        return "日志过长，仅显示末尾 2000 行。\n\n\(tail)"
    }

    static func reason(action: String, outputs: [GitOutput], conflict: Bool) -> String {
        if conflict {
            if action == "拉取" { return "拉取产生冲突。" }
            return "合并产生冲突，解决后提交以完成合并。"
        }
        let combined = outputs.map { $0.stdoutText + "\n" + $0.stderrText }.joined(separator: "\n")
        let lower = combined.lowercased()
        if outputs.contains(where: { $0.exitCode == 124 }) {
            return "Git 命令执行超时，已自动终止。"
        }
        if outputs.contains(where: { $0.exitCode == -1 && $0.stderrText.contains("未找到 git") }) {
            return "未找到 git。"
        }
        if lower.contains("index.lock") || lower.contains("unable to create") && lower.contains(".lock") {
            return "仓库被锁定，请稍后重试。"
        }
        if lower.contains("authentication failed")
            || lower.contains("permission denied (publickey)")
            || lower.contains("could not read from remote")
            || lower.contains("terminal prompts disabled")
            || lower.contains("could not read username") {
            return "需要登录。请使用系统已配置的 SSH 或 credential helper。"
        }
        if lower.contains("non-fast-forward")
            || lower.contains("failed to push some refs")
            || lower.contains("updates were rejected") {
            return "远程拒绝推送。"
        }
        if lower.contains("no tracking information") || lower.contains("no upstream") {
            return "当前分支没有上游。请先推送，或为该分支设置上游。"
        }
        if lower.contains("does not appear to be a git repository")
            || lower.contains("no configured push destination")
            || lower.contains("no such remote") {
            if action == "推送" { return "无法推送：没有名为 origin 的远程。" }
            return "该仓库没有远程。"
        }
        if lower.contains("conflict") || lower.contains("fix conflicts") {
            if action == "拉取" { return "拉取产生冲突。" }
            if action == "合并" { return "合并产生冲突，解决后提交以完成合并。" }
        }
        return "Git 命令执行失败。"
    }
}
