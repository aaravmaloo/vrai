import SwiftUI
import VraiCore
import VraiGit

extension WindowModel {
    public func openBlame(path: String, revision: String? = nil) {
        store.fileFocus = FileFocus(path: path, revision: revision)
        show(.blame)
    }

    public func openFileHistory(path: String) {
        store.fileFocus = FileFocus(path: path)
        show(.fileHistory)
    }
}
