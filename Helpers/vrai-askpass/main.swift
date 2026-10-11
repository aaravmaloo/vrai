import Darwin
import Foundation

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data(("vrai-askpass: " + message + "\n").utf8))
    exit(code)
}

func connectSocket(_ path: String) -> Int32 {
    let bytes = Array(path.utf8)
    var address = sockaddr_un()
    guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { fail("the socket path is too long: \(path)") }
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
        for (index, byte) in bytes.enumerated() { raw[index] = byte }
    }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { fail("could not open a socket") }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard connected == 0 else { fail("Vrai is not answering prompts at \(path)") }
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    return fd
}

func send(_ data: Data, to fd: Int32) {
    data.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return }
        var offset = 0
        while offset < raw.count {
            let written = write(fd, base + offset, raw.count - offset)
            if written < 0, errno == EINTR { continue }
            if written <= 0 { fail("could not send the prompt to Vrai") }
            offset += written
        }
    }
}

func receive(from fd: Int32, within timeout: Double) -> [UInt8] {
    let deadline = Date().addingTimeInterval(timeout)
    var reply: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 { fail("Vrai did not answer within \(Int(timeout.rounded())) seconds, so the prompt was declined.", code: 2) }
        var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ready = poll(&poller, 1, Int32(min(remaining, 1) * 1000) + 1)
        if ready < 0, errno == EINTR { continue }
        if ready < 0 { fail("lost the connection to Vrai") }
        if ready == 0 { continue }
        let count = read(fd, &buffer, buffer.count)
        if count < 0, errno == EINTR { continue }
        if count < 0 { fail("lost the connection to Vrai") }
        if count == 0 { return reply }
        reply.append(contentsOf: buffer[0..<count])
    }
}

let environment = ProcessInfo.processInfo.environment
let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")
guard let socketPath = environment["VRAI_ASKPASS_SOCKET"], !socketPath.isEmpty else {
    fail("no Vrai window is answering prompts, so \"\(prompt)\" was declined.")
}
let timeout = environment["VRAI_ASKPASS_TIMEOUT"].flatMap(Double.init).map { max(0.1, $0) } ?? 120

var request = ["prompt": prompt]
if let kind = environment["SSH_ASKPASS_PROMPT"] { request["ssh"] = kind }
if let context = environment["VRAI_ASKPASS_CONTEXT"] { request["context"] = context }
guard let payload = try? JSONSerialization.data(withJSONObject: request) else { fail("could not encode the prompt") }

let connection = connectSocket(socketPath)
send(payload, to: connection)
shutdown(connection, SHUT_WR)
let reply = receive(from: connection, within: timeout)
close(connection)

guard reply.first == UInt8(ascii: "1") else { exit(1) }
FileHandle.standardOutput.write(Data(reply.dropFirst()) + Data("\n".utf8))
exit(0)
