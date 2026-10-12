import Observation
import SwiftUI
import VraiCore

public struct Toast: Identifiable {
    public let id = UUID()
    public var tone: Tone = .neutral
    public var message: String
    public var detail: String?
    public var icon: String?
    public var action: String?
    public var onAction: (@MainActor () -> Void)?
    public var busy = false
    public var timeout: TimeInterval?

    public init(tone: Tone = .neutral, message: String, detail: String? = nil, icon: String? = nil, action: String? = nil, timeout: TimeInterval? = nil, busy: Bool = false, onAction: (@MainActor () -> Void)? = nil) {
        self.tone = tone
        self.message = message
        self.detail = detail
        self.icon = icon
        self.action = action
        self.timeout = timeout
        self.busy = busy
        self.onAction = onAction
    }

    public static let brief: TimeInterval = 2.2
    public static let standard: TimeInterval = 4.5
    public static let withAction: TimeInterval = 7
    public static let failure: TimeInterval = 9

    var duration: TimeInterval {
        if let timeout { return timeout }
        if tone == .danger { return Self.failure }
        return action == nil ? Self.standard : Self.withAction
    }
}

@MainActor
@Observable
public final class ToastCenter {
    public private(set) var toasts: [Toast] = []
    public static let limit = 3

    public init() {}

    @discardableResult
    public func show(_ toast: Toast) -> UUID {
        toasts = Array((toasts + [toast]).suffix(Self.limit))
        AccessibilityNotification.Announcement(toast.detail.map { toast.message + ". " + $0 } ?? toast.message).post()
        let id = toast.id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(toast.duration))
            self?.dismiss(id)
        }
        return id
    }

    public func dismiss(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }
}

struct ToastView: View {
    let toast: Toast
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Vrai.Space.s10) {
            if toast.busy {
                Spinner()
            } else {
                Symbol(toast.icon ?? (toast.tone == .neutral ? "checkmark.circle" : toast.tone.symbol), font: Font.Vrai.title3)
                    .foregroundStyle(toast.tone == .neutral ? Color.Vrai.accentText : toast.tone.color)
            }
            VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                Text(toast.message)
                    .font(Font.Vrai.body)
                    .foregroundStyle(Color.Vrai.text)
                if let detail = toast.detail {
                    Text(detail)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            if let action = toast.action {
                Button {
                    dismiss()
                    toast.onAction?()
                } label: {
                    Text(action).font(Font.Vrai.headline)
                }
                .buttonStyle(ToastActionStyle())
            }
            Button(action: dismiss) {
                Symbol("xmark", font: Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .frame(width: Vrai.Space.s20, height: Vrai.Space.s20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dismiss", bundle: .module))
        }
        .padding(.vertical, Vrai.Space.s8)
        .padding(.leading, Vrai.Space.s12)
        .padding(.trailing, Vrai.Space.s8)
        .frame(minWidth: Vrai.Size.field, maxWidth: Metrics.toastMax)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Vrai.Radius.lg, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isStaticText)
    }
}

struct ToastActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.Vrai.accentText)
            .padding(.horizontal, Vrai.Space.s8)
            .frame(height: Vrai.Size.controlSm)
            .background(configuration.isPressed ? Color.Vrai.fillActive : Color.clear, in: RoundedRectangle(cornerRadius: Vrai.Radius.sm, style: .continuous))
            .contentShape(Rectangle())
    }
}

struct ToastHost: View {
    @Environment(ToastCenter.self) private var center
    @Environment(\.vraiReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Vrai.Space.s8) {
            ForEach(center.toasts) { toast in
                ToastView(toast: toast) { center.dismiss(toast.id) }
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Vrai.Space.s16)
        .padding(.bottom, Vrai.Space.s16)
        .animation(reduceMotion ? Animation.Vrai.standardFast : Animation.Vrai.outBase, value: center.toasts.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Notifications", bundle: .module))
    }
}
