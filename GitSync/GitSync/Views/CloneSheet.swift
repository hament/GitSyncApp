import AppKit
import SwiftUI

struct CloneSheet: View {
  @Bindable var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var address = ""
  @State private var destinationPath = ""
  @State private var lastSuggestedPath = ""

  private var canClone: Bool {
    (try? GitClone.source(address)) != nil && (try? GitClone.destination(destinationPath)) != nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(L10n.text("克隆仓库", "Clone Repository"), systemImage: "square.and.arrow.down")
        .font(.headline)
      VStack(alignment: .leading, spacing: 6) {
        Text(L10n.text("仓库地址", "Repository URL"))
          .font(.subheadline)
        TextField("https://host/owner/repo.git", text: $address)
          .textFieldStyle(.roundedBorder)
          .disableAutocorrection(true)
          .accessibilityIdentifier("clone.address")
        if !address.isEmpty, let error = addressError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .disabled(model.isWorking)
      VStack(alignment: .leading, spacing: 6) {
        Text(L10n.text("项目保存路径", "Destination Path"))
          .font(.subheadline)
        HStack(spacing: 8) {
          TextField(L10n.text("本地项目文件夹路径", "Local project folder path"), text: $destinationPath)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("clone.destination")
          Button {
            chooseParentFolder()
          } label: {
            Image(systemName: "folder")
              .frame(width: 24, height: 24)
          }
          .help(L10n.text("选择保存位置", "Choose destination parent folder"))
          .accessibilityLabel(L10n.text("选择保存位置", "Choose destination parent folder"))
        }
        if !model.isWorking, !destinationPath.isEmpty, let error = destinationError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .disabled(model.isWorking)
      if model.isWorking {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text(model.refreshLabel.localized)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
      if let error = model.cloneError {
        if model.cloneAuthenticationGuide != nil {
          DisclosureGroup(L10n.text("Git 错误详情", "Git Error Details")) {
            errorLog(error).frame(height: 80)
          }
        } else {
          errorLog(error).frame(maxHeight: 160)
        }
      }
      if let guide = model.cloneAuthenticationGuide, !model.isWorking {
        CloneAuthenticationView(guide: guide, canRetry: canClone) {
          Task { await model.cloneRepository(address: address, destinationPath: destinationPath) }
        }
        .id(guide)
      }
      HStack {
        Spacer()
        Button(model.isWorking ? L10n.text("取消克隆", "Cancel Clone") : L10n.text("取消", "Cancel")) {
          if model.isWorking { model.cancelCurrentOperation() } else { dismiss() }
        }
        .keyboardShortcut(.cancelAction)
        if model.cloneAuthenticationGuide == nil {
          Button("Clone") {
            Task { await model.cloneRepository(address: address, destinationPath: destinationPath) }
          }
          .disabled(model.isWorking || !canClone)
          .keyboardShortcut(.defaultAction)
        }
      }
    }
    .padding(20)
    .frame(width: 580)
    .interactiveDismissDisabled(model.isWorking)
    .onChange(of: address) {
      model.cloneError = nil
      model.cloneAuthenticationGuide = nil
      updateSuggestedPath()
    }
    .onChange(of: destinationPath) { model.cloneError = nil }
  }

  private func errorLog(_ error: String) -> some View {
    ScrollView {
      Text(error)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.red)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var addressError: String? {
    do {
      _ = try GitClone.source(address)
      return nil
    } catch { return error.localizedDescription }
  }

  private var destinationError: String? {
    do {
      _ = try GitClone.destination(destinationPath)
      return nil
    } catch { return error.localizedDescription }
  }

  private func updateSuggestedPath() {
    guard let source = try? GitClone.source(address) else { return }
    let parent =
      lastSuggestedPath.isEmpty
      ? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
      : URL(fileURLWithPath: lastSuggestedPath, isDirectory: true).deletingLastPathComponent()
    let suggested = parent.appendingPathComponent(source.suggestedName, isDirectory: true).path
    if destinationPath.isEmpty || destinationPath == lastSuggestedPath {
      destinationPath = suggested
    }
    lastSuggestedPath = suggested
  }

  private func chooseParentFolder() {
    guard let window = NSApplication.shared.keyWindow else { return }
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = L10n.text("选择", "Choose")
    let current = (destinationPath as NSString).expandingTildeInPath
    panel.directoryURL =
      current.isEmpty ? nil : URL(fileURLWithPath: current).deletingLastPathComponent()
    panel.beginSheetModal(for: window) { response in
      MainActor.assumeIsolated {
        guard response == .OK, let parent = panel.url else { return }
        let name = (try? GitClone.source(address).suggestedName) ?? "repository"
        destinationPath = parent.appendingPathComponent(name, isDirectory: true).path
        lastSuggestedPath = destinationPath
      }
    }
  }
}
