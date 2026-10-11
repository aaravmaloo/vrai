import Foundation

public enum ConfigKeys {
    public static let defaultBranch = "init.defaultBranch"
    public static let pullRebase = "pull.rebase"
    public static let pullFastForward = "pull.ff"
    public static let rebaseAutostash = "rebase.autoStash"
    public static let mergeAutostash = "merge.autoStash"
    public static let rerere = "rerere.enabled"
    public static let diffAlgorithm = "diff.algorithm"
    public static let commitSign = "commit.gpgsign"
    public static let tagSign = "tag.gpgSign"
    public static let signFormat = "gpg.format"
    public static let signingKey = "user.signingkey"
    public static let userName = "user.name"
    public static let userEmail = "user.email"
    public static let maintenanceRepo = "maintenance.repo"
    public static let hooksPath = "core.hooksPath"
}

extension PullMode {
    public init(config: ConfigValues) {
        let rebase = config.value(ConfigKeys.pullRebase)?.lowercased() ?? ""
        if ConfigBool.parse(rebase) == true || rebase == "merges" || rebase == "interactive" || rebase == "m" || rebase == "i" {
            self = .rebase
        } else if config.value(ConfigKeys.pullFastForward)?.lowercased() == "only" {
            self = .fastForwardOnly
        } else {
            self = .merge
        }
    }

    public var writes: [ConfigWrite] {
        switch self {
        case .merge: [ConfigWrite(ConfigKeys.pullRebase, "false"), ConfigWrite(ConfigKeys.pullFastForward, nil)]
        case .rebase: [ConfigWrite(ConfigKeys.pullRebase, "true"), ConfigWrite(ConfigKeys.pullFastForward, nil)]
        case .fastForwardOnly: [ConfigWrite(ConfigKeys.pullRebase, "false"), ConfigWrite(ConfigKeys.pullFastForward, "only")]
        }
    }
}

public enum DiffAlgorithm: String, Sendable, Hashable, CaseIterable {
    case myers
    case minimal
    case patience
    case histogram

    public init(config: ConfigValues) {
        self = config.value(ConfigKeys.diffAlgorithm).flatMap { DiffAlgorithm(rawValue: $0.lowercased()) } ?? .myers
    }
}

public enum SignFormat: String, Sendable, Hashable, CaseIterable {
    case ssh
    case openpgp
    case x509

    public init(config: ConfigValues) {
        self = config.value(ConfigKeys.signFormat).flatMap { SignFormat(rawValue: $0.lowercased()) } ?? .openpgp
    }

    public var keyType: String {
        switch self {
        case .ssh: "SSH"
        case .openpgp: "GPG"
        case .x509: "X.509"
        }
    }
}

public struct SigningSettings: Sendable, Hashable {
    public var commits: Bool
    public var tags: Bool
    public var format: SignFormat
    public var key: String?

    public init(config: ConfigValues) {
        commits = config.bool(ConfigKeys.commitSign) ?? false
        tags = config.bool(ConfigKeys.tagSign) ?? false
        format = SignFormat(config: config)
        key = config.value(ConfigKeys.signingKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    public static func writes(signing: Bool) -> [ConfigWrite] {
        [ConfigWrite(ConfigKeys.commitSign, ConfigBool.string(signing)), ConfigWrite(ConfigKeys.tagSign, ConfigBool.string(signing))]
    }
}

public struct Identity: Sendable, Hashable {
    public var name: String?
    public var email: String?

    public init(name: String? = nil, email: String? = nil) {
        self.name = name
        self.email = email
    }

    public init(config: ConfigValues) {
        name = config.value(ConfigKeys.userName)
        email = config.value(ConfigKeys.userEmail)
    }

    public var isEmpty: Bool { (name ?? "").isEmpty && (email ?? "").isEmpty }

    public static func isValidEmail(_ text: String) -> Bool {
        text.wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]+/) != nil
    }
}
