import Foundation
import Testing
@testable import VraiGit

struct CoverageHomeCommandsTests {
    static let a = OID(String(repeating: "a", count: 40))!
    static let b = OID(String(repeating: "b", count: 40))!
    static let c = OID(String(repeating: "c", count: 40))!

    @Test func rangeDiffComparesTheBranchWithItsReflog() {
        #expect(RangeDiffCommands.beforeRebase(branch: "feature/x").display == "git range-diff refs/heads/feature/x@{1}...refs/heads/feature/x")
        #expect(RangeDiffCommands.beforeRebase(branch: "feature/x").access == .read)
        #expect(RangeDiffCommands.lastMove(branch: "main").arguments == ["log", "-g", "-1", "--format=%gs", "refs/heads/main", "--"])
        #expect(RangeDiffCommands.previousTip(branch: "main").arguments == ["rev-parse", "--verify", "--quiet", "refs/heads/main@{1}"])
        #expect(RangeDiffCommands.wasRebase("rebase (finish): refs/heads/x onto 1234\n"))
        #expect(RangeDiffCommands.wasRebase("rebase (replay): onto main"))
        #expect(RangeDiffCommands.wasRebase("Rebase -i (finish): returning to refs/heads/x"))
        #expect(!RangeDiffCommands.wasRebase("commit: Graph: snap nodes"))
        #expect(!RangeDiffCommands.wasRebase(""))
    }

    @Test func diffToolAndAnnotate() {
        #expect(SharedCommands.diffTool(path: "Sources/a b.swift").display == "git difftool --tool=opendiff --no-prompt -- \"Sources/a b.swift\"")
        #expect(SharedCommands.diffTool(path: "README.md", staged: true).arguments == ["difftool", "--tool=opendiff", "--no-prompt", "--cached", "--", "README.md"])
        #expect(SharedCommands.diffTool(path: "README.md").access == .read)
        #expect(PlacesCommands.annotate(path: "README.md", at: nil).arguments == ["annotate", "--", "README.md"])
        #expect(PlacesCommands.annotate(path: "README.md", at: "").arguments == ["annotate", "--", "README.md"])
        #expect(PlacesCommands.annotate(path: "README.md", at: Self.a.rawValue).arguments == ["annotate", Self.a.rawValue, "--", "README.md"])
    }

    @Test func conflictLabelsComeFromTheMarkers() {
        let merge = "a\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> mira/spike/metal-graph\nb\n"
        #expect(ConflictLabels.parse(merge) == ConflictLabels(ours: "HEAD", base: "base", theirs: "mira/spike/metal-graph"))
        let diff3 = "<<<<<<< HEAD\r\nours\r\n||||||| merged common ancestors\r\nbase\r\n=======\r\ntheirs\r\n>>>>>>> 1a2b3c4 (Graph: snap nodes)\r\n"
        #expect(ConflictLabels.parse(diff3) == ConflictLabels(ours: "HEAD", base: "merged common ancestors", theirs: "1a2b3c4 (Graph: snap nodes)"))
        #expect(ConflictLabels.parse("<<<<<<< .merge_file_abc\nx\n=======\ny\n>>>>>>> .merge_file_def\n") == nil)
        #expect(ConflictLabels.parse("no markers\n") == nil)
        #expect(ConflictLabels.parse("<<<<<<<\nx\n=======\ny\n>>>>>>>\n") == nil)
    }

    @Test func relabelReplacesOnlyTemporaryLabels() {
        let labels = ConflictLabels(ours: "HEAD", base: "base", theirs: "feature/x")
        let text = "keep\n<<<<<<< .merge_file_6mCVlD\nours\n||||||| .merge_file_sJHpnP\nbase\n=======\ntheirs\n>>>>>>> .merge_file_8tP7HN\n<<<<<<< HEAD\n"
        #expect(ConflictRestart.relabel(text, with: labels) == "keep\n<<<<<<< HEAD\nours\n||||||| base\nbase\n=======\ntheirs\n>>>>>>> feature/x\n<<<<<<< HEAD\n")
        let crlf = "<<<<<<< .merge_file_a\r\nx\r\n=======\r\ny\r\n>>>>>>> .merge_file_b\r\n"
        #expect(ConflictRestart.relabel(crlf, with: labels) == "<<<<<<< HEAD\r\nx\r\n=======\r\ny\r\n>>>>>>> feature/x\r\n")
        #expect(ConflictRestart.relabel("plain\n", with: labels) == "plain\n")
    }

    @Test func unmergedStagesParseLsFilesOutput() {
        let data = Data("100644 \(Self.a.rawValue) 1\tREADME.md\u{0}100755 \(Self.b.rawValue) 2\tREADME.md\u{0}100644 \(Self.c.rawValue) 3\tREADME.md\u{0}".utf8)
        let stages = UnmergedStages.parse(data)
        #expect(stages.base == .init(oid: Self.a, mode: "100644"))
        #expect(stages.ours == .init(oid: Self.b, mode: "100755"))
        #expect(stages.theirs == .init(oid: Self.c, mode: "100644"))
        #expect(stages.isContentConflict)
        let deleted = UnmergedStages.parse(Data("100644 \(Self.a.rawValue) 1\tx\u{0}100644 \(Self.b.rawValue) 2\tx\u{0}".utf8))
        #expect(!deleted.isContentConflict)
    }

    @Test func startOverRunsMergeOneFileAndMergeIndex() {
        let stages = UnmergedStages(base: .init(oid: Self.a, mode: "100644"), ours: .init(oid: Self.b, mode: "100644"), theirs: .init(oid: Self.c, mode: "100755"))
        let one = ConflictRestart.mergeOneFile(path: "Sources/Lane Layout.swift", stages: stages)
        #expect(one.arguments == ["merge-one-file", Self.a.rawValue, Self.b.rawValue, Self.c.rawValue, "Sources/Lane Layout.swift", "100644", "100644", "100755"])
        #expect(one.subcommand == "merge-one-file")
        #expect(one.acceptedExitCodes == [0, 1])
        #expect(one.risk == .destructive)
        #expect(one.access == .write)
        let added = ConflictRestart.mergeOneFile(path: "x", stages: UnmergedStages(ours: .init(oid: Self.b, mode: "100644"), theirs: .init(oid: Self.c, mode: "100644")))
        #expect(added.arguments == ["merge-one-file", "", Self.b.rawValue, Self.c.rawValue, "x", "", "100644", "100644"])
        let index = ConflictRestart.mergeIndex(paths: ["a.swift", "b.swift"])
        #expect(index.display == "git merge-index -o -q git-merge-one-file -- a.swift b.swift")
        #expect(index.acceptedExitCodes.contains(2))
        #expect(!index.acceptedExitCodes.contains(128))
        #expect(ConflictRestart.mergedBlob(path: "a.swift").arguments == ["cat-file", "blob", "AUTO_MERGE:a.swift"])
    }

    @Test func rerereCommands() {
        #expect(ConflictRestart.rerereRemaining.display == "git rerere remaining")
        #expect(ConflictRestart.rerereEnabled.arguments == ["config", "-z", "--get", "rerere.enabled"])
        #expect(ConflictRestart.remaining("a.swift\nSources/b c.swift\n") == ["a.swift", "Sources/b c.swift"])
        #expect(ConflictRestart.remaining("").isEmpty)
    }

    @Test func messageCommands() {
        let heads = [
            MergeHead(oid: Self.a, name: "feature/x", kind: .branch),
            MergeHead(oid: Self.b, name: "origin/main", kind: .remoteBranch),
            MergeHead(oid: Self.c, name: "v1.0.0", kind: .tag),
            MergeHead(oid: Self.a, name: "1a2b3c4", kind: .commit)
        ]
        let merge = MessageCommands.mergeMessage(heads)
        #expect(merge.arguments == ["fmt-merge-msg"])
        #expect(String(decoding: merge.stdin ?? Data(), as: UTF8.self) == "\(Self.a.rawValue)\t\tbranch 'feature/x' of .\n\(Self.b.rawValue)\t\tremote-tracking branch 'origin/main' of .\n\(Self.c.rawValue)\t\ttag 'v1.0.0' of .\n\(Self.a.rawValue)\t\tcommit '1a2b3c4'\n")
        #expect(MessageCommands.cleanup("x").arguments == ["stripspace", "--strip-comments"])
        #expect(MessageCommands.cleanup("x", stripComments: false).arguments == ["stripspace"])
        #expect(MessageCommands.cleanup("x\n").stdin == Data("x\n".utf8))
        let trailer = Trailer.coAuthor(name: "Mira Okafor", email: "mira@vrai.app")
        #expect(trailer.text == "Co-authored-by: Mira Okafor <mira@vrai.app>")
        #expect(Trailer.coAuthor(name: "Mira", email: "").text == "Co-authored-by: Mira")
        let add = MessageCommands.addTrailers([trailer, Trailer(key: "Reviewed-by", value: "Avery")], to: "Fix\n")
        #expect(add.display == "git interpret-trailers --if-exists addIfDifferent --trailer \"Co-authored-by: Mira Okafor <mira@vrai.app>\" --trailer \"Reviewed-by: Avery\"")
        #expect(add.access == .read)
    }

    @Test func packCommands() {
        let pack = PackCommands.packLoose(into: "/repo/.git/objects/pack/pack")
        #expect(pack.arguments == ["pack-objects", "--revs", "--all", "--reflog", "--indexed-objects", "--unpacked", "--incremental", "--local", "--non-empty", "-q", "/repo/.git/objects/pack/pack"])
        #expect(pack.stdin == Data())
        #expect(pack.risk == .safe)
        #expect(pack.access == .write)
        let unpack = PackCommands.unpack(Data([1, 2, 3]))
        #expect(unpack.arguments == ["unpack-objects", "-r", "-q"])
        #expect(unpack.stdin == Data([1, 2, 3]))
        #expect(PackCommands.redundant().arguments == ["pack-redundant", "--i-still-use-this", "--all"])
        #expect(PackCommands.redundant(confirmed: false).arguments == ["pack-redundant", "--all"])
        #expect(PackCommands.redundant().access == .read)
        #expect(PackCommands.redundant().acceptedExitCodes == [0, 128, 129])
        let listed = "/repo/.git/objects/pack/pack-1111.idx\n/repo/.git/objects/pack/pack-1111.pack\n/repo/.git/objects/pack/pack-2222.idx\n/repo/.git/objects/pack/pack-2222.pack\n"
        #expect(PackCommands.redundantPacks(listed) == ["pack-1111", "pack-2222"])
        #expect(PackCommands.redundantPacks("").isEmpty)
    }

    @Test func maintenanceForEveryRepository() {
        #expect(MaintenanceCommands.runEverywhere().display == "git for-each-repo --config=maintenance.repo --keep-going maintenance run")
        #expect(MaintenanceCommands.runEverywhere().subcommand == "for-each-repo")
        #expect(MaintenanceCommands.runEverywhere(keepGoing: false).arguments == ["for-each-repo", "--config=maintenance.repo", "maintenance", "run"])
        #expect(MaintenanceCommands.runEverywhere(keepGoing: false).acceptedExitCodes == [0])
        let stderr = "fatal: cannot change to '/tmp/gone/repo': No such file or directory\nerror: something else\nfatal: cannot change to '/Users/a b/x': No such file or directory\n"
        #expect(MaintenanceCommands.unreachable(stderr) == ["/tmp/gone/repo", "/Users/a b/x"])
        #expect(MaintenanceCommands.unreachable("").isEmpty)
    }

    @Test func credentialHelpersParse() {
        let keychain = CredentialHelper("osxkeychain")
        #expect(keychain.kind == .keychain)
        #expect(keychain.name == "osxkeychain")
        #expect(CredentialHelper("/usr/local/bin/git-credential-osxkeychain").kind == .keychain)
        let cache = CredentialHelper("cache --timeout=900 --socket /tmp/vrai sock")
        #expect(cache.kind == .cache)
        #expect(cache.socket == "/tmp/vrai")
        #expect(CredentialHelper("cache --socket=/tmp/s").socket == "/tmp/s")
        let store = CredentialHelper("store --file=/tmp/vrai/git-credentials")
        #expect(store.kind == .store)
        #expect(store.file == "/tmp/vrai/git-credentials")
        #expect(store.socket == nil)
        #expect(CredentialHelper("store --file ~/.vrai-credentials").file == "~/.vrai-credentials")
        #expect(CredentialHelper("store").file == nil)
        #expect(CredentialHelper("manager").kind == .other)
        #expect(CredentialHelper("!f() { echo password=x; }; f").kind == .other)
        #expect(CredentialHelper.effective(["osxkeychain", "", "cache", "store"]).map(\.kind) == [.cache, .store])
        #expect(CredentialHelper.effective(["osxkeychain"]).map(\.kind) == [.keychain])
        #expect(CredentialHelper.effective(["osxkeychain", ""]).isEmpty)
        #expect(CredentialHelper.effective([]).isEmpty)
    }

    @Test func credentialHelperCommands() {
        #expect(CredentialHelperCommands.configured.arguments == ["config", "-z", "--get-all", "credential.helper"])
        #expect(CredentialHelperCommands.choose(.cache).map(\.arguments) == [
            ["config", "--global", "--unset-all", "credential.helper"],
            ["config", "--global", "--add", "credential.helper", ""],
            ["config", "--global", "--add", "credential.helper", "cache"]
        ])
        #expect(CredentialHelperCommands.choose(.keychain).last?.arguments.last == "osxkeychain")
        #expect(CredentialHelperCommands.choose(.store).last?.arguments.last == "store")
        #expect(CredentialHelperCommands.choose(.other).isEmpty)
        #expect(CredentialHelperCommands.forgetCached().display == "git credential-cache exit")
        #expect(CredentialHelperCommands.forgetCached(socket: "/tmp/s").arguments == ["credential-cache", "--socket", "/tmp/s", "exit"])
        let erase = CredentialHelperCommands.eraseStored(file: "/tmp/creds", scheme: "https")
        #expect(erase.arguments == ["credential-store", "--file=/tmp/creds", "erase"])
        #expect(erase.stdin == Data("protocol=https\n\n".utf8))
        #expect(erase.risk == .destructive)
        #expect(CredentialHelperCommands.eraseStored(scheme: "http").arguments == ["credential-store", "erase"])
        #expect(CredentialHelperCommands.expandHome("~/.git-credentials", home: "/Users/avery/") == "/Users/avery/.git-credentials")
        #expect(CredentialHelperCommands.expandHome("/abs/path", home: "/Users/avery") == "/abs/path")
        #expect(CredentialHelperCommands.expandHome("~/x", home: nil) == "~/x")
    }
}
