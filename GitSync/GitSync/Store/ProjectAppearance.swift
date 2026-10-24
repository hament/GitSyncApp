import SwiftUI

nonisolated enum ProjectTheme: String, Codable, CaseIterable, Identifiable, Sendable {
  case blue
  case teal
  case green
  case rose
  case violet
  case amber
  case orange
  case sky
  case red
  case lime
  case yellow
  case none

  var id: String { rawValue }

  var color: Color {
    switch self {
    case .blue: Color(red: 0.12, green: 0.43, blue: 0.86)
    case .teal: Color(red: 0.02, green: 0.49, blue: 0.52)
    case .green: Color(red: 0.19, green: 0.53, blue: 0.28)
    case .rose: Color(red: 0.77, green: 0.24, blue: 0.40)
    case .violet: Color(red: 0.48, green: 0.33, blue: 0.76)
    case .amber: Color(red: 0.68, green: 0.43, blue: 0.05)
    case .orange: Color(red: 0.79, green: 0.33, blue: 0.08)
    case .sky: Color(red: 0.03, green: 0.48, blue: 0.70)
    case .red: Color(red: 0.74, green: 0.15, blue: 0.18)
    case .lime: Color(red: 0.43, green: 0.53, blue: 0.07)
    case .yellow: Color(red: 0.96, green: 0.78, blue: 0.10)
    case .none: Color(nsColor: .controlAccentColor)
    }
  }

  var headerColor: Color { self == .none ? .primary : color }
  var headerBackground: Color { self == .none ? .clear : color.opacity(0.08) }
  var checkmarkColor: Color { self == .yellow ? .black : .white }

  @MainActor var title: String {
    switch self {
    case .blue: L10n.text("蓝色", "Blue")
    case .teal: L10n.text("青色", "Teal")
    case .green: L10n.text("绿色", "Green")
    case .rose: L10n.text("玫红", "Rose")
    case .violet: L10n.text("紫色", "Violet")
    case .amber: L10n.text("琥珀", "Amber")
    case .orange: L10n.text("橙色", "Orange")
    case .sky: L10n.text("天蓝", "Sky")
    case .red: L10n.text("红色", "Red")
    case .lime: L10n.text("黄绿", "Lime")
    case .yellow: L10n.text("黄色", "Yellow")
    case .none: L10n.text("不使用主题色", "No project color")
    }
  }
}

@MainActor
@Observable
final class ProjectAppearance {
  static let shared = ProjectAppearance()
  private var themes: [String: String]
  @ObservationIgnored private let defaults: UserDefaults
  private let key = "projectColorThemes"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    themes = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
  }

  private func repositoryKey(_ path: String) -> String {
    URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL.path
  }

  func theme(for path: String?, fallback: ProjectTheme = .blue) -> ProjectTheme {
    guard let path, let value = themes[repositoryKey(path)] else { return fallback }
    if value == "graphite" { return .yellow }
    return ProjectTheme(rawValue: value) ?? fallback
  }

  func setTheme(_ theme: ProjectTheme, for path: String) {
    themes[repositoryKey(path)] = theme.rawValue
    defaults.set(themes, forKey: key)
  }
}

private struct ProjectThemeKey: EnvironmentKey {
  static let defaultValue = ProjectTheme.blue
}

extension EnvironmentValues {
  var projectTheme: ProjectTheme {
    get { self[ProjectThemeKey.self] }
    set { self[ProjectThemeKey.self] = newValue }
  }
}

extension View {
  func projectTheme(_ theme: ProjectTheme) -> some View {
    tint(theme == .none ? nil : theme.color)
      .accentColor(theme == .none ? nil : theme.color)
      .environment(\.projectTheme, theme)
  }
}
