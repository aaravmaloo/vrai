import Darwin
import Foundation

struct IndexStamp: Equatable, Sendable {
    var inode: UInt64
    var size: Int64
    var seconds: Int
    var nanoseconds: Int

    init?(path: String) {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        inode = UInt64(info.st_ino)
        size = Int64(info.st_size)
        seconds = info.st_mtimespec.tv_sec
        nanoseconds = info.st_mtimespec.tv_nsec
    }
}

extension RepositoryStore {
    var indexPath: String? {
        snapshot?.gitDir.appending(path: "index").path(percentEncoded: false)
    }

    func noteOwnIndex() {
        ownIndexStamp = indexPath.flatMap { IndexStamp(path: $0) }
    }

    func isOwnIndexChange(_ changes: Set<RepositoryChange>) -> Bool {
        guard changes == [.index], let own = ownIndexStamp, let path = indexPath else { return false }
        return IndexStamp(path: path) == own
    }
}
