import SwiftUI
import VraiCore
import VraiGit

public struct SettingsView: View {
    @Environment(AppModel.self) private var app

    public init() {}

    public var body: some View {
        @Bindable var preferences = app.preferences
        Form {
            Picker(String(localized: "Appearance", bundle: .module), selection: $preferences.theme) {
                Text("Match the system", bundle: .module).tag(Preferences.Theme.system)
                Text("Light", bundle: .module).tag(Preferences.Theme.light)
                Text("Dark", bundle: .module).tag(Preferences.Theme.dark)
            }
            Picker(String(localized: "Density", bundle: .module), selection: $preferences.density) {
                Text("Compact", bundle: .module).tag(Preferences.Density.compact)
                Text("Regular", bundle: .module).tag(Preferences.Density.regular)
                Text("Comfortable", bundle: .module).tag(Preferences.Density.comfortable)
            }
            Toggle(String(localized: "Show the Welcome window when no repository is open", bundle: .module), isOn: $preferences.welcomeOnLaunch)
            Toggle(String(localized: "Expert mode", bundle: .module), isOn: $preferences.expert)
        }
        .formStyle(.grouped)
        .frame(width: Vrai.Size.sheet)
        .background(WindowConfigurator(launch: app.launch))
        .tint(Color.Vrai.accent)
    }
}
