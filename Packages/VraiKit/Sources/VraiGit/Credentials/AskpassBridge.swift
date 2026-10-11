import Darwin
import Foundation

public struct AskpassRequest: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case username
        case password
        case passphrase
        case confirm
        case other
    }

    public var prompt: String
    public var kind: Kind
    public var context: String?
    public var url: String?

    public init(prompt: String, sshPrompt: String? = nil, context: String? = nil) {
        self.prompt = prompt
        self.context = context
        url = prompt.firstMatch(of: /for '([^']+)'/).map { String($0.output.1) }
        let lowered = prompt.lowercased()
        if sshPrompt == "confirm" || lowered.contains("(yes/no") {
            kind = .confirm
        } else if lowered.hasPrefix("username") {
            kind = .username
        } else if lowered.contains("passphrase") {
            kind = .passphrase
        } else if lowered.contains("password") {
            kind = .password
        } else {
            kind = .other
        }
    }

    public var host: String? {
        guard let url else { return nil }
        if let parsed = RemoteURL(url) { return parsed.hostAndPort }
        return nil
    }

    public var username: String? { url.flatMap { RemoteURL($0)?.user } }
}

public final class AskpassBridge: @unchecked Sendable {
    public typealias Handler = @Sendable (AskpassRequest) async -> String?

    public static let socketVariable = "VRAI_ASKPASS_SOCKET"
    public static let contextVariable = "VRAI_ASKPASS_CONTEXT"
    public static let timeoutVariable = "VRAI_ASKPASS_TIMEOUT"
    public static let helperName = "vrai-askpass"
    public static let maximumSocketPathLength = 103
    static let maximumRequest = 65_536

    public let socketURL: URL
    private let lock = NSLock()
    private var handler: Handler?
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.aaravmaloo.vrai.askpass", qos: .userInitiated)

    public init(socketURL: URL, handler: Handler? = nil) throws {
        self.socketURL = socketURL
        self.handler = handler
        try listen()
    }

    deinit {
        if source != nil { unlink(socketURL.path(percentEncoded: false)) }
        source?.cancel()
    }

    public static func socketURL(in directory: URL) -> URL {
        directory.appending(path: "askpass-" + String(UUID().uuidString.prefix(8)).lowercased() + ".sock")
    }

    public static func bundledHelper(in bundle: Bundle = .main) -> URL? {
        bundle.url(forAuxiliaryExecutable: helperName)
    }

    public func setHandler(_ handler: Handler?) {
        lock.withLock { self.handler = handler }
    }

    public var isListening: Bool { lock.withLock { source != nil } }

    public func close() {
        let current = lock.withLock { () -> DispatchSourceRead? in
            let current = source
            source = nil
            return current
        }
        guard let current else { return }
        unlink(socketURL.path(percentEncoded: false))
        current.cancel()
    }

    public func environment(_ environment: GitEnvironment, helper: URL, context: String? = nil) -> GitEnvironment {
        var environment = environment
        environment.askpass = helper.path(percentEncoded: false)
        environment.base[Self.socketVariable] = socketURL.path(percentEncoded: false)
        if let context { environment.base[Self.contextVariable] = context }
        return environment
    }

    private func listen() throws {
        let path = socketURL.path(percentEncoded: false)
        let bytes = Array(path.utf8)
        guard bytes.count <= Self.maximumSocketPathLength else { throw GitError(.unknown(exit: ENAMETOOLONG, stderr: "the askpass socket path is longer than \(Self.maximumSocketPathLength) bytes: \(path)")) }
        try FileManager.default.createDirectory(at: socketURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw GitError(.unknown(exit: errno, stderr: "socket")) }
        var address = Self.address(bytes)
        unlink(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 16) == 0 else {
            let code = errno
            Darwin.close(fd)
            throw GitError(.unknown(exit: code, stderr: "could not listen at \(path)"))
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending(fd) }
        source.setCancelHandler {
            Darwin.close(fd)
            unlink(path)
        }
        lock.withLock { self.source = source }
        source.resume()
    }

    static func address(_ bytes: [UInt8]) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            for (index, byte) in bytes.enumerated() where index < raw.count - 1 { raw[index] = byte }
        }
        return address
    }

    private func acceptPending(_ listener: Int32) {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 { return }
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
                Darwin.close(client)
                continue
            }
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.serve(client) }
        }
    }

    private func serve(_ client: Int32) {
        guard let request = Self.readRequest(client) else {
            Self.reply(client, answer: nil)
            return
        }
        let handler = lock.withLock { self.handler }
        guard let handler else {
            Self.reply(client, answer: nil)
            return
        }
        Task.detached {
            let answer = await handler(request)
            Self.reply(client, answer: answer)
        }
    }

    static func readRequest(_ client: Int32) -> AskpassRequest? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < maximumRequest {
            let count = read(client, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            if count <= 0 { break }
            data.append(contentsOf: buffer[0..<count])
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: String], let prompt = object["prompt"] else { return nil }
        return AskpassRequest(prompt: prompt, sshPrompt: object["ssh"], context: object["context"])
    }

    static func reply(_ client: Int32, answer: String?) {
        var payload = Data(answer == nil ? "0".utf8 : "1".utf8)
        if let answer { payload.append(Data(answer.utf8)) }
        payload.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = write(client, base + offset, raw.count - offset)
                if written < 0, errno == EINTR { continue }
                if written <= 0 { break }
                offset += written
            }
        }
        Darwin.close(client)
    }
}
