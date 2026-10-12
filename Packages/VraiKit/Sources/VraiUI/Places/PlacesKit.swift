import SwiftUI
import VraiCore
import VraiGit

struct PlacesPane<ListContent: View, Detail: View>: View {
    var showDetail: Bool
    var backLabel: String
    var back: () -> Void
    @ViewBuilder let list: () -> ListContent
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        GeometryReader { geometry in
            let width = WidthClass(width: geometry.size.width)
            Group {
                if width.isNarrow {
                    if showDetail {
                        VStack(spacing: 0) {
                            PlacesBackBar(label: backLabel, action: back)
                            detail()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        list()
                    }
                } else {
                    HStack(spacing: 0) {
                        list()
                            .frame(width: Vrai.Size.inspector + Vrai.Space.s40)
                            .hairline(.trailing)
                        detail()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .environment(\.widthClass, width)
        }
        .clipped()
        .background(Color.Vrai.bg)
    }
}

struct PlacesBackBar: View {
    let label: String
    let action: () -> Void

    var body: some View {
        HStack {
            Button(action: action) {
                HStack(spacing: Vrai.Space.s4) {
                    Symbol("chevron.left", font: Font.Vrai.callout)
                    Text(label).lineLimit(1)
                }
            }
            .buttonStyle(VraiButtonStyle(variant: .plain, size: .small))
            .accessibilityIdentifier("places-back")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Vrai.Space.s8)
        .frame(height: Metrics.paneBarHeight)
        .hairline(.bottom)
    }
}

struct PlacesListHeader<Leading: View, Trailing: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Vrai.Space.s8) {
            leading()
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Font.Vrai.headline)
                    .foregroundStyle(Color.Vrai.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let caption {
                    Text(caption)
                        .font(Font.Vrai.caption)
                        .foregroundStyle(Color.Vrai.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            trailing()
        }
        .padding(.vertical, Vrai.Space.s6)
        .padding(.leading, Vrai.Space.s16)
        .padding(.trailing, Vrai.Space.s8)
        .frame(minHeight: Metrics.barHeight)
        .hairline(.bottom)
    }
}

extension PlacesListHeader where Leading == EmptyView {
    init(title: String, caption: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(title: title, caption: caption, leading: { EmptyView() }, trailing: trailing)
    }
}

extension PlacesListHeader where Leading == EmptyView, Trailing == EmptyView {
    init(title: String, caption: String? = nil) {
        self.init(title: title, caption: caption, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

struct PlacesRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var meta: String?
    var mono = false
    var selected = false
    var identifier: String?
    let action: () -> Void
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        Button(action: action) {
            HStack(spacing: Vrai.Space.s10) {
                leading()
                VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                    Text(title)
                        .font(mono ? Font.Vrai.code : Font.Vrai.body)
                        .foregroundStyle(Color.Vrai.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Font.Vrai.caption)
                            .foregroundStyle(Color.Vrai.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let meta {
                    Text(meta)
                        .font(Font.Vrai.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
                trailing()
            }
            .padding(.horizontal, Vrai.Space.s10)
            .padding(.vertical, Vrai.Space.s4)
            .frame(minHeight: Vrai.Size.row + Vrai.Space.s8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: Vrai.Radius.sm, selected: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier ?? title)
    }
}

extension PlacesRow where Leading == PlacesRowIcon {
    init(icon: String, title: String, subtitle: String? = nil, meta: String? = nil, mono: Bool = false, selected: Bool = false, identifier: String? = nil, action: @escaping () -> Void, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(title: title, subtitle: subtitle, meta: meta, mono: mono, selected: selected, identifier: identifier, action: action, leading: { PlacesRowIcon(name: icon) }, trailing: trailing)
    }
}

struct PlacesRowIcon: View {
    let name: String

    var body: some View {
        Symbol(name, font: Font.Vrai.title3)
            .foregroundStyle(Color.Vrai.textTertiary)
            .frame(width: Vrai.Size.icon)
    }
}

struct PlacesList<Content: View>: View {
    var label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Vrai.Space.s2) {
                content()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
            .padding(Vrai.Space.s6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

struct PlacesDetail<Content: View>: View {
    var identifier: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Vrai.Space.s20) {
                content()
            }
            .padding(.vertical, Vrai.Space.s20)
            .padding(.horizontal, Vrai.Space.s24)
            .frame(maxWidth: Vrai.Size.sheetWide, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier ?? "places-detail")
    }
}

struct PlacesTitle<Badges: View>: View {
    let title: String
    var mono = false
    @ViewBuilder let badges: () -> Badges

    var body: some View {
        HStack(spacing: Vrai.Space.s12) {
            Text(title)
                .font(mono ? Font.Vrai.title2.monospaced() : Font.Vrai.title2)
                .foregroundStyle(Color.Vrai.text)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            badges()
        }
    }
}

extension PlacesTitle where Badges == EmptyView {
    init(title: String, mono: Bool = false) {
        self.init(title: title, mono: mono) { EmptyView() }
    }
}

struct PlacesActionsRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        FlowLayout(spacing: Vrai.Space.s8, lineSpacing: Vrai.Space.s8) {
            content()
        }
    }
}

struct PlacesEmpty<Actions: View>: View {
    let icon: String
    let title: String
    var message: String?
    var small = false
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                EmptyStateView(icon: icon, title: title, message: message, small: small, actions: actions)
                    .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.Vrai.bg)
    }
}

extension PlacesEmpty where Actions == EmptyView {
    init(icon: String, title: String, message: String? = nil, small: Bool = false) {
        self.init(icon: icon, title: title, message: message, small: small) { EmptyView() }
    }
}

struct PlacesBusyButton: View {
    let title: String
    let icon: String
    var variant: ButtonVariant = .secondary
    var size: ButtonSize = .regular
    var busy = false
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: size.gap) {
                if busy { Spinner() } else { Symbol(icon, font: size.iconFont) }
                Text(title)
            }
        }
        .buttonStyle(VraiButtonStyle(variant: variant, size: size))
        .disabled(busy)
        .accessibilityIdentifier(identifier ?? title)
    }
}

struct PlacesLoadFailed: View {
    let title: String
    let error: GitError
    let retry: () -> Void

    var body: some View {
        PlacesEmpty(icon: "exclamationmark.triangle", title: title, message: PlacesCopy.message(for: error), small: true) {
            VraiButton(title: String(localized: "Try again", bundle: .module), icon: "arrow.clockwise", size: .small, action: retry)
        }
    }
}

enum PlacesLoad<Value: Sendable>: Sendable {
    case loading
    case loaded(Value)
    case failed(GitError)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }
}

enum PlacesCopy {
    static func message(for error: GitError) -> String {
        (ErrorCopy.places(error) ?? ErrorCopy(error)).message
    }

    static func name(_ path: String) -> String {
        let last = URL(filePath: path).lastPathComponent
        return last.isEmpty ? path : last
    }
}
