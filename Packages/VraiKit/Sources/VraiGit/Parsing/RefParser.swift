import Foundation

public struct RefListing: Sendable, Hashable {
    public var branches: [Branch]
    public var remoteBranches: [RemoteBranch]
    public var remoteHeads: [String: String]
    public var tags: [Tag]
}

public enum RefParser {
    static let fields = [
        "%(refname)", "%(objectname)", "%(objecttype)", "%(*objectname)", "%(upstream)", "%(upstream:track,nobracket)",
        "%(HEAD)", "%(worktreepath)", "%(creatordate:unix)", "%(taggername)", "%(contents:subject)", "%(symref)",
        "%(if)%(contents:signature)%(then)signed%(end)"
    ]

    public static let format = fields.map { $0 + "%00" }.joined()

    public static let command = GitCommand.read(["for-each-ref", "--format=" + format, "refs/heads", "refs/remotes", "refs/tags"])

    public static func parse(_ data: Data, remotes: [String] = []) -> RefListing {
        var listing = RefListing(branches: [], remoteBranches: [], remoteHeads: [:], tags: [])
        let byLength = remotes.sorted { $0.count > $1.count }
        let bytes = Array(data)
        var records: [ArraySlice<UInt8>] = []
        var start = 0
        var i = 0
        while i < bytes.count {
            if bytes[i] == 0, i + 1 < bytes.count, bytes[i + 1] == 0x0A {
                records.append(bytes[start...i])
                start = i + 2
                i += 2
                continue
            }
            i += 1
        }
        for record in records {
            var parts = record.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
            if parts.last == "" { parts.removeLast() }
            guard parts.count >= fields.count else { continue }
            let ref = parts[0]
            guard let oid = OID(parts[1]) else { continue }
            if ref.hasPrefix("refs/heads/") {
                let name = String(ref.dropFirst("refs/heads/".count))
                let track = parts[5]
                var branch = Branch(name: name, tip: oid)
                if parts[4].hasPrefix("refs/remotes/") { branch.upstream = String(parts[4].dropFirst("refs/remotes/".count)) }
                else if parts[4].hasPrefix("refs/heads/") { branch.upstream = String(parts[4].dropFirst("refs/heads/".count)) }
                else if !parts[4].isEmpty { branch.upstream = parts[4] }
                branch.upstreamGone = track == "gone"
                if let ahead = track.firstMatch(of: /ahead (\d+)/) { branch.ahead = Int(ahead.output.1) ?? 0 }
                if let behind = track.firstMatch(of: /behind (\d+)/) { branch.behind = Int(behind.output.1) ?? 0 }
                branch.isCurrent = parts[6] == "*"
                branch.worktreePath = parts[7].isEmpty ? nil : parts[7]
                listing.branches.append(branch)
            } else if ref.hasPrefix("refs/remotes/") {
                let rest = String(ref.dropFirst("refs/remotes/".count))
                let remote = byLength.first { rest.hasPrefix($0 + "/") } ?? String(rest.split(separator: "/", maxSplits: 1).first ?? "")
                let name = String(rest.dropFirst(remote.count + 1))
                if !parts[11].isEmpty {
                    let target = parts[11].hasPrefix("refs/remotes/" + remote + "/") ? String(parts[11].dropFirst(("refs/remotes/" + remote + "/").count)) : parts[11]
                    listing.remoteHeads[remote] = target
                    continue
                }
                listing.remoteBranches.append(RemoteBranch(remote: remote, name: name, tip: oid))
            } else if ref.hasPrefix("refs/tags/") {
                let name = String(ref.dropFirst("refs/tags/".count))
                let annotated = parts[2] == "tag"
                let target = annotated ? (OID(parts[3]) ?? oid) : oid
                listing.tags.append(Tag(
                    name: name,
                    target: target,
                    annotated: annotated,
                    tagger: annotated && !parts[9].isEmpty ? parts[9] : nil,
                    date: annotated ? ParseSupport.date(parts[8]) : nil,
                    message: annotated && !parts[10].isEmpty ? parts[10] : nil,
                    signature: parts[12] == "signed" ? .unchecked : .unsigned
                ))
            }
        }
        return listing
    }
}
