import Foundation
import Observation

nonisolated enum AppLanguage: String, CaseIterable, Sendable {
  case english = "en"
  case simplifiedChinese = "zh-Hans"

  static func systemDefault(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage
  {
    guard let preferred = preferredLanguages.first else { return .english }
    let language = Locale.Language(identifier: preferred)
    return language.languageCode?.identifier == "zh" && language.script?.identifier == "Hans"
      ? .simplifiedChinese : .english
  }

  var locale: Locale { Locale(identifier: rawValue) }
}

@MainActor
@Observable
final class LanguageSettings {
  static let shared = LanguageSettings()
  static let preferenceKey = "appLanguage"

  var language: AppLanguage {
    didSet { defaults.set(language.rawValue, forKey: Self.preferenceKey) }
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages)
  {
    self.defaults = defaults
    language =
      defaults.string(forKey: Self.preferenceKey).flatMap(AppLanguage.init(rawValue:))
      ?? AppLanguage.systemDefault(preferredLanguages: preferredLanguages)
  }
}

nonisolated struct LocalizedText: Hashable, Sendable, ExpressibleByStringLiteral {
  let chinese: String
  let english: String

  init(_ chinese: String, _ english: String) {
    self.chinese = chinese
    self.english = english
  }

  init(stringLiteral value: String) {
    self.init(value, value)
  }

  @MainActor var localized: String {
    LanguageSettings.shared.language == .simplifiedChinese ? chinese : english
  }

  var isEmpty: Bool { chinese.isEmpty && english.isEmpty }
}

nonisolated enum L10n {
  @MainActor static func text(_ chinese: String, _ english: String) -> String {
    LocalizedText(chinese, english).localized
  }

  static func message(_ chinese: String, _ english: String) -> LocalizedText {
    LocalizedText(chinese, english)
  }
}
