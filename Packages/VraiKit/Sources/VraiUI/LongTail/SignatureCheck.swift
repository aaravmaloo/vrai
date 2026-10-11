import SwiftUI
import VraiCore
import VraiGit

struct SignatureCheck: View {
    enum Target: Hashable {
        case commit(OID)
        case tag(String)
    }

    let target: Target
    let state: SignatureState
    var signer: String?
    var compact = false
    @Environment(RepositoryStore.self) private var store
    @State private var shown = false

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            SignatureBadge(state: state, signer: signer, compact: compact)
        }
        .buttonStyle(.plain)
        .disabled(state == .unsigned)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            SignaturePopover(target: target, store: store)
        }
        .accessibilityHint(Text("Shows who signed it", bundle: .module))
    }
}

struct SignaturePopover: View {
    let target: SignatureCheck.Target
    let store: RepositoryStore
    @State private var report: SignatureReport?
    @Environment(\.expert) private var expert

    var body: some View {
        VStack(alignment: .leading, spacing: Vrai.Space.s8) {
            if let report {
                HStack(spacing: Vrai.Space.s8) {
                    Symbol(report.good ? "checkmark.seal" : "xmark.seal", font: Font.Vrai.title3)
                        .foregroundStyle(report.good ? Color.Vrai.success : Color.Vrai.danger)
                    Text(title(report))
                        .font(Font.Vrai.headline)
                        .foregroundStyle(Color.Vrai.text)
                        .lineLimit(2)
                }
                if let keyType = report.keyType {
                    LongTailKeyValue(key: String(localized: "Key", bundle: .module), value: keyType)
                }
                if let fingerprint = report.fingerprint {
                    LongTailKeyValue(key: String(localized: "Fingerprint", bundle: .module), value: fingerprint, mono: true)
                }
                if expert || !report.good, !report.message.isEmpty {
                    Text(report.message)
                        .font(Font.Vrai.codeSmall)
                        .foregroundStyle(Color.Vrai.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: Vrai.Space.s8) {
                    Spinner()
                    Text("Checking the signature\u{2026}", bundle: .module)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textSecondary)
                }
            }
        }
        .padding(Vrai.Space.s16)
        .frame(width: Vrai.Size.field + Vrai.Space.s64)
        .task {
            switch target {
            case .commit(let id): report = await store.verifySignature(commit: id)
            case .tag(let name): report = await store.verifySignature(tag: name)
            }
        }
    }

    func title(_ report: SignatureReport) -> String {
        guard report.good else { return String(localized: "The signature doesn't check out", bundle: .module) }
        return String(localized: "Signed by \(report.signer ?? String(localized: "a trusted key", bundle: .module))", bundle: .module)
    }
}
