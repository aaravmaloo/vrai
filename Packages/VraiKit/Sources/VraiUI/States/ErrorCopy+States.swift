import Foundation
import VraiGit

extension ErrorCopy {
    static func writing(_ error: Error) -> String {
        if let error = error as? GitError { return ErrorCopy(error).message }
        return String(localized: "\(describe(error)) Check that the folder exists and you can write to it, then try again.", bundle: .module)
    }

    static func reading(_ error: Error) -> String {
        if let error = error as? GitError { return ErrorCopy(error).message }
        return String(localized: "\(describe(error)) Try again. If it keeps failing, check the repository in Terminal.", bundle: .module)
    }

    static func describe(_ error: Error) -> String {
        let text = (error as NSError).localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasSuffix(".") ? text : text + "."
    }
}
