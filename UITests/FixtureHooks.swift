import Foundation

enum FixtureHooks {
    static func useOriginals(copy: String, original: String) {
        let fm = FileManager.default
        guard let walker = fm.enumerator(atPath: copy) else { return }
        for case let path as String in walker {
            let name = (path as NSString).lastPathComponent
            if ["objects", "logs", "refs", "modules"].contains(name) {
                walker.skipDescendants()
                continue
            }
            guard path == ".git/config" || path.hasSuffix("/.git/config") else { continue }
            let hooks = original + "/" + String(path.dropLast("config".count)) + "hooks"
            var folder: ObjCBool = false
            guard fm.fileExists(atPath: hooks, isDirectory: &folder), folder.boolValue, let handle = FileHandle(forWritingAtPath: copy + "/" + path) else { continue }
            handle.seekToEndOfFile()
            handle.write(Data("[core]\n\thooksPath = \(hooks)\n".utf8))
            try? handle.close()
        }
    }
}
