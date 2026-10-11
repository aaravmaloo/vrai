import Foundation

public enum PackCommands {
    public static let usageExit: Int32 = 129

    public static func packLoose(into base: String) -> GitCommand {
        GitCommand(["pack-objects", "--revs", "--all", "--reflog", "--indexed-objects", "--unpacked", "--incremental", "--local", "--non-empty", "-q", base], stdin: Data(), access: .write)
    }

    public static func unpack(_ pack: Data) -> GitCommand {
        GitCommand(["unpack-objects", "-r", "-q"], stdin: pack, access: .write)
    }

    public static func redundant(confirmed: Bool = true) -> GitCommand {
        .read(["pack-redundant"] + (confirmed ? ["--i-still-use-this"] : []) + ["--all"], acceptedExitCodes: [0, 128, usageExit])
    }

    public static func redundantPacks(_ output: String) -> [String] {
        output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasSuffix(".pack") }
            .map { URL(filePath: $0).deletingPathExtension().lastPathComponent }
    }

    public static func foundNoPacks(_ result: GitResult) -> Bool {
        result.exitCode == 128 && result.errorOutput.contains("Zero packs found")
    }
}
