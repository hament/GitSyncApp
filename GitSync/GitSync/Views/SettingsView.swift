import SwiftUI

struct SettingsButton: View {
  var model: AppModel? = nil
  @Environment(\.projectTheme) private var theme
  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      Image(systemName: "gearshape")
        .font(.system(size: 16))
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .help(L10n.text("设置", "Settings"))
    .accessibilityLabel(L10n.text("设置", "Settings"))
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      SettingsView(model: model, close: { isPresented = false })
        .environment(\.locale, LanguageSettings.shared.language.locale)
        .projectTheme(theme)
    }
  }
}

struct SettingsView: View {
  var model: AppModel? = nil
  var close: () -> Void = {}
  @Bindable private var settings = LanguageSettings.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(L10n.text("设置", "Settings"))
        .font(.headline)
      Divider()
      Picker(L10n.text("语言", "Language"), selection: $settings.language) {
        Text("English").tag(AppLanguage.english)
        Text("简体中文").tag(AppLanguage.simplifiedChinese)
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("settings.language")
      if let model {
        Divider()
        Button {
          close()
          model.showProjectInfo = true
        } label: {
          Label(L10n.text("项目信息", "Project Info"), systemImage: "info.circle")
        }
        .disabled(model.repositoryPath == nil)
        .accessibilityIdentifier("settings.projectInfo")
        Divider()
        Text(L10n.text("项目主题色", "Project color"))
          .font(.subheadline)
        LazyVGrid(
          columns: Array(repeating: GridItem(.fixed(32), spacing: 10), count: 6),
          alignment: .leading, spacing: 10
        ) {
          ForEach(ProjectTheme.allCases) { theme in
            Button {
              model.projectTheme = theme
            } label: {
              ZStack {
                if theme == .none {
                  Image(systemName: "circle.slash")
                    .font(.system(size: 27))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                } else {
                  Circle()
                    .fill(theme.color)
                    .frame(width: 28, height: 28)
                    .overlay {
                      if model.projectTheme == theme {
                        Image(systemName: "checkmark")
                          .font(.system(size: 12, weight: .bold))
                          .foregroundStyle(theme.checkmarkColor)
                      }
                    }
                }
              }
              .frame(width: 32, height: 32)
              .overlay {
                if theme == .none && model.projectTheme == .none {
                  Circle().stroke(theme.color, lineWidth: 2)
                }
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(theme.title)
            .accessibilityLabel(theme.title)
            .accessibilityValue(model.projectTheme == theme ? L10n.text("已选择", "Selected") : "")
          }
        }
      }
    }
    .padding(20)
    .frame(width: 300)
  }
}

struct ProjectInfoView: View {
  var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var address = ""
  @State private var loading = true
  @State private var errorMessage: String?
  @State private var copiedValue: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(L10n.text("项目信息", "Project Info")).font(.headline)
      Divider()
      information(L10n.text("仓库名称", "Repository name"), value: model.repositoryDisplayName)
      if loading {
        ProgressView().controlSize(.small)
      } else {
        information(L10n.text("仓库地址", "Repository URL"), value: address)
        if let errorMessage {
          Text(errorMessage).foregroundStyle(.secondary).font(.caption)
        }
      }
      HStack {
        Spacer()
        Button(L10n.text("关闭", "Close")) { dismiss() }
          .keyboardShortcut(.cancelAction)
      }
    }
    .padding(24)
    .frame(width: 500)
    .task(id: model.repositoryPath) { await loadAddress() }
    .task(id: copiedValue) {
      guard copiedValue != nil else { return }
      do { try await Task.sleep(for: .seconds(2)) } catch { return }
      copiedValue = nil
    }
  }

  private func information(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.subheadline).foregroundStyle(.secondary)
      HStack(alignment: .top) {
        Text(value.isEmpty ? L10n.text("未配置远程仓库", "No remote configured") : value)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button {
          NSPasteboard.general.clearContents()
          if NSPasteboard.general.setString(value, forType: .string) { copiedValue = title }
        } label: {
          Image(systemName: copiedValue == title ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .disabled(value.isEmpty)
        .help(L10n.text("复制", "Copy"))
        .accessibilityLabel(L10n.text("复制", "Copy") + " " + title)
      }
    }
  }

  private func loadAddress() async {
    loading = true
    address = ""
    errorMessage = nil
    guard let path = model.repositoryPath else {
      loading = false
      return
    }
    let cwd = URL(fileURLWithPath: path, isDirectory: true)
    let remotes = await GitClient.run(args: ["remote"], cwd: cwd)
    guard !Task.isCancelled, model.repositoryPath == path else { return }
    let names = remotes.stdoutText.split(separator: "\n").map(String.init)
    if !remotes.succeeded {
      errorMessage = L10n.text("无法读取仓库地址", "Unable to read repository URL")
    } else if let remote = names.contains("origin") ? "origin" : names.first {
      let output = await GitClient.run(args: ["remote", "get-url", remote], cwd: cwd)
      guard !Task.isCancelled, model.repositoryPath == path else { return }
      if output.succeeded {
        address = output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
      } else {
        errorMessage = L10n.text("无法读取仓库地址", "Unable to read repository URL")
      }
    }
    loading = false
  }
}
