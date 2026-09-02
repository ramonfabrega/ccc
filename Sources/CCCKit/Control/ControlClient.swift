import Darwin
import Foundation

/// The CLI's side of the socket: connect, send one line, read one line.
/// Plain blocking BSD sockets — the caller is a command that exits.
public struct ControlClient: Sendable {
    public var path: String

    public init(path: String = ControlSocket.defaultPath) {
        self.path = path
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case unreachable(String)
        case malformedResponse
        public var description: String {
            switch self {
            case .unreachable(let p): return "no ccc is serving \(p) — open the app or run `ccc attach <id> --headless`"
            case .malformedResponse: return "malformed response from ccc"
            }
        }
    }

    /// True when something accepts connections at the path right now.
    public func isReachable() -> Bool {
        guard let fd = connect() else { return false }
        close(fd)
        return true
    }

    public func send(_ request: ControlRequest) throws -> ControlResponse {
        guard let fd = connect() else { throw Error.unreachable(path) }
        defer { close(fd) }

        var payload = try JSONEncoder().encode(request)
        payload.append(UInt8(ascii: "\n"))
        var offset = 0
        while offset < payload.count {
            let n = payload.withUnsafeBytes { raw in
                Darwin.write(fd, raw.baseAddress! + offset, payload.count - offset)
            }
            if n < 0 {
                if errno == EINTR { continue }
                throw Error.unreachable(path)
            }
            offset += n
        }

        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { break }
            received.append(contentsOf: buffer[..<n])
            if received.last == UInt8(ascii: "\n") { break }
        }
        // `.ccc`, not a bare decoder: the response carries the server's
        // BuildInfo, and a server older than v0.1.6 sends no `name` — this
        // side ran the command, so this side is what supplies it.
        guard let response = try? JSONDecoder.ccc.decode(ControlResponse.self, from: received) else {
            throw Error.malformedResponse
        }
        return response
    }

    private func connect() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let ok = withUnsafeMutableBytes(of: &address.sun_path) { buffer -> Bool in
            let bytes = Array(path.utf8)
            guard bytes.count < buffer.count else { return false }
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
            return true
        }
        guard ok else { close(fd); return nil }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { close(fd); return nil }
        return fd
    }
}
