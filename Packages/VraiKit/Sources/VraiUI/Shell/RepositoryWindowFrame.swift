import SwiftUI

public struct RepositoryWindowFrame: View {
    @State private var destination: SidebarDestination? = .history
    @State private var showsInspector = false

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarFrame(destination: $destination)
                .navigationSplitViewColumnWidth(Vrai.Size.sidebar)
        } detail: {
            EmptyRepositoryContent()
                .inspector(isPresented: $showsInspector) {
                    Color.Vrai.bg
                        .inspectorColumnWidth(Vrai.Size.inspector)
                }
        }
        .toolbar {
            RepositoryToolbarFrame(showsInspector: $showsInspector)
        }
        .tint(Color.Vrai.accent)
    }
}

struct SidebarFrame: View {
    @Binding var destination: SidebarDestination?

    var body: some View {
        List(selection: $destination) {
            Section {
                ForEach(SidebarDestination.allCases, id: \.self) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .font(Font.Vrai.body)
                        .tag(item)
                }
            } header: {
                Text("Workspace", bundle: .module)
                    .font(Font.Vrai.captionStrong)
                    .foregroundStyle(Color.Vrai.textTertiary)
            }
        }
        .listStyle(.sidebar)
    }
}

struct EmptyRepositoryContent: View {
    var body: some View {
        ContentUnavailableView {
            Label(String(localized: "No repository open", bundle: .module), systemImage: "folder")
                .font(Font.Vrai.title1)
        } description: {
            Text("Open a repository and its history shows up here.", bundle: .module)
                .font(Font.Vrai.body)
                .foregroundStyle(Color.Vrai.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.Vrai.bg)
    }
}

struct RepositoryToolbarFrame: ToolbarContent {
    @Binding var showsInspector: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup {
            PendingToolbarButton(title: String(localized: "Fetch", bundle: .module), systemImage: "arrow.triangle.2.circlepath")
            PendingToolbarButton(title: String(localized: "Pull", bundle: .module), systemImage: "arrow.down.to.line")
            PendingToolbarButton(title: String(localized: "Push", bundle: .module), systemImage: "arrow.up.to.line")
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            PendingToolbarButton(title: String(localized: "New branch", bundle: .module), systemImage: "arrow.triangle.branch")
            PendingToolbarButton(title: String(localized: "Merge", bundle: .module), systemImage: "arrow.triangle.merge")
            PendingToolbarButton(title: String(localized: "Rebase", bundle: .module), systemImage: "arrow.triangle.swap")
        }
        ToolbarSpacer(.fixed)
        ToolbarItem {
            PendingToolbarButton(title: String(localized: "Stash changes", bundle: .module), systemImage: "tray.and.arrow.down")
        }
        ToolbarSpacer(.fixed)
        ToolbarItem {
            PendingToolbarButton(title: String(localized: "Search actions, branches, commits", bundle: .module), systemImage: "magnifyingglass")
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            PendingToolbarButton(title: String(localized: "Console", bundle: .module), systemImage: "terminal")
            Toggle(isOn: $showsInspector) {
                Label(String(localized: "Inspector", bundle: .module), systemImage: "sidebar.right")
            }
            .help(showsInspector ? String(localized: "Hide inspector", bundle: .module) : String(localized: "Show inspector", bundle: .module))
        }
    }
}

struct PendingToolbarButton: View {
    let title: String
    let systemImage: String

    var body: some View {
        Button(title, systemImage: systemImage) {}
            .help(title)
            .disabled(true)
    }
}
