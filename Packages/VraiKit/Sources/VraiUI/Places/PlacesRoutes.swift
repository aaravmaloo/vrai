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

    public func openFileHistory(path: String, selecting id: OID) {
        store.fileFocus = FileFocus(path: path, revision: id.rawValue)
        show(.fileHistory)
    }
}
