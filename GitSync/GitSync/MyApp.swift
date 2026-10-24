import SwiftUI

@main
struct MyApp: App {
  var body: some Scene {
    WindowGroup("Git Sync", for: ProjectWindowRequest.self) { $request in
      ProjectWindowView(request: $request)
    } defaultValue: {
      ProjectWindowRequest(restoreLastRepository: true)
    }
    .windowStyle(.titleBar)
    .windowToolbarStyle(.expanded)
    .defaultSize(width: 1100, height: 720)
    .commands { ProjectWindowCommands() }

    WindowGroup(L10n.text("差异对比", "Compare Changes"), for: ComparisonRequest.self) { $request in
      if let request {
        ComparisonView(request: request)
          .environment(\.locale, LanguageSettings.shared.language.locale)
          .projectTheme(ProjectAppearance.shared.theme(for: request.repositoryPath))
      }
    }
    .windowStyle(.titleBar)
    .windowToolbarStyle(.expanded)
    .defaultSize(width: 1100, height: 720)
  }
}

private struct ProjectWindowRequest: Codable, Hashable {
  var id = UUID()
  var restoreLastRepository: Bool
  var repositoryPath: String?
}

private struct ProjectWindowView: View {
  @Binding var request: ProjectWindowRequest
  @State private var model: AppModel

  init(request: Binding<ProjectWindowRequest>) {
    _request = request
    _model = State(initialValue: AppModel(windowID: request.wrappedValue.id))
  }

  var body: some View {
    MainView(
      model: model, restoreLastRepository: request.restoreLastRepository,
      restoreRepositoryPath: request.repositoryPath
    )
    .environment(\.locale, LanguageSettings.shared.language.locale)
    .projectTheme(model.projectTheme)
    .onDisappear { model.closeWindow() }
    .onChange(of: model.repositoryPath) { _, path in
      request.repositoryPath = path
    }
  }
}

private struct ProjectWindowCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button(L10n.text("新建项目窗口", "New Project Window")) {
        openWindow(value: ProjectWindowRequest(restoreLastRepository: false))
      }
      .keyboardShortcut("n", modifiers: [.command, .shift])
    }
  }
}
