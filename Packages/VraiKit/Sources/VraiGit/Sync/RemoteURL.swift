import Foundation

public struct RemoteURL: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case network
        case scp
        case local
        case helper
    }

    public static let schemes: Set<String> = ["ssh", "git", "http", "https", "ftp", "ftps", "file", "git+ssh", "ssh+git"]

    public var kind: Kind
    public var scheme: String?
    public var user: String?
    public var host: String?
    public var port: Int?
    public var path: String

    public init?(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !value.contains(where: { $0.isNewline || $0 == "\0" }) else { return nil }
        if let helper = value.firstMatch(of: /^([A-Za-z][A-Za-z0-9+.-]*)::(.+)$/) {
            kind = .helper
            scheme = String(helper.output.1).lowercased()
            path = String(helper.output.2)
            return
        }
        if let match = value.firstMatch(of: /^([A-Za-z][A-Za-z0-9+.-]*):\/\/(.*)$/) {
            let scheme = String(match.output.1).lowercased()
            guard Self.schemes.contains(scheme) else { return nil }
            let rest = String(match.output.2)
            self.scheme = scheme
            if scheme == "file" {
                guard rest.hasPrefix("/") || rest.hasPrefix("localhost/") else { return nil }
                kind = .local
                path = rest.hasPrefix("localhost/") ? String(rest.dropFirst("localhost".count)) : rest
                return
            }
            guard !rest.contains(where: \.isWhitespace) else { return nil }
            let slash = rest.firstIndex(of: "/") ?? rest.endIndex
            var authority = String(rest[..<slash])
            path = String(rest[slash...])
            if let at = authority.lastIndex(of: "@") {
                user = String(authority[..<at])
                authority = String(authority[authority.index(after: at)...])
            }
            if authority.hasPrefix("["), let close = authority.firstIndex(of: "]") {
                host = String(authority[authority.index(after: authority.startIndex)..<close])
                let tail = authority[authority.index(after: close)...]
                if tail.hasPrefix(":") { port = Int(tail.dropFirst()) }
            } else if let colon = authority.lastIndex(of: ":") {
                host = String(authority[..<colon])
                let digits = authority[authority.index(after: colon)...]
                guard digits.isEmpty || Int(digits) != nil else { return nil }
                port = Int(digits)
            } else {
                host = authority
            }
            guard let host, !host.isEmpty, host.allSatisfy({ $0.isLetter || $0.isNumber || "-._:".contains($0) }) else { return nil }
            kind = .network
            return
        }
        if value.hasPrefix("/") || value.hasPrefix("./") || value.hasPrefix("../") || value.hasPrefix("~") || value == "." || value == ".." {
            kind = .local
            path = value
            return
        }
        if let scp = value.firstMatch(of: /^(?:([^@\/\s:]+)@)?([A-Za-z0-9._-]+|\[[0-9A-Fa-f:.]+\]):(.*)$/) {
            let rest = String(scp.output.3)
            guard !rest.isEmpty, !rest.hasPrefix("//"), !rest.contains(where: \.isWhitespace) else { return nil }
            kind = .scp
            scheme = "ssh"
            user = scp.output.1.map(String.init)
            host = String(scp.output.2).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            path = rest
            return
        }
        return nil
    }

    public static func isValid(_ text: String) -> Bool { RemoteURL(text) != nil }

    public var hostAndPort: String? {
        guard let host else { return nil }
        return port.map { host + ":" + String($0) } ?? host
    }

    public var repositoryPath: String {
        var value = path
        while value.hasPrefix("/") { value.removeFirst() }
        while value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix(".git") { value.removeLast(4) }
        if kind == .scp, value.hasPrefix("~") { value.removeFirst() }
        return value
    }

    public var displayName: String {
        guard kind == .network || kind == .scp, let host else { return repositoryPath }
        return host + "/" + repositoryPath
    }
}

extension GitError {
    public var remoteURL: String? {
        guard let text = result?.errorOutput else { return nil }
        if let quoted = text.firstMatch(of: /(?:for|access|to|from) '([^']+)'/) { return String(quoted.output.1).trimmingSuffix("/") }
        if let to = text.firstMatch(of: /^To (\S+)$/.anchorsMatchLineEndings()) { return String(to.output.1) }
        return nil
    }

    public var host: String? {
        switch code {
        case .authFailed(let host), .networkUnreachable(let host): host ?? remoteURL.flatMap { RemoteURL($0)?.host }
        default: remoteURL.flatMap { RemoteURL($0)?.host }
        }
    }
}
