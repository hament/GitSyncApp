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
            SettingsView(model: model)
                .environment(\.locale, LanguageSettings.shared.language.locale)
                .projectTheme(theme)
        }
    }
}

struct SettingsView: View {
    var model: AppModel? = nil
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
                Text(L10n.text("项目主题色", "Project color"))
                    .font(.subheadline)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 10), count: 6), alignment: .leading, spacing: 10) {
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
