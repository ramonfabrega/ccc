import Foundation
import Network

/// Unix-socket listener for the agent surface (scry's `ControlServer`).
/// Line-delimited JSON, one request per connection. Traffic is a human or
/// an agent typing, not a firehose, so everything runs on the main queue,
/// where the pane lives.
@MainActor
public final class ControlServer {
    private var listener: NWListener?
    public let path: String
    private let handle: @MainActor (ControlRequest) async -> ControlResponse

    public init(path: String = ControlSocket.defaultPath,
                handle: @escaping @MainActor (ControlRequest) async -> ControlResponse) {
        self.path = path
        self.handle = handle
    }

    public enum StartError: Error, CustomStringConvertible {
        case alreadyServed(path: String)
        case listenFailed(String)
        public var description: String {
            switch self {
            case .alreadyServed(let p): return "another ccc already serves \(p)"
            case .listenFailed(let m): return "control socket failed to start: \(m)"
            }
        }
    }

    /// Refuses to start when a live server already owns the path (a stale
    /// socket file from a crashed run is removed and taken over).
    public func start() throws {
        if ControlClient(path: path).isReachable() {
            throw StartError.alreadyServed(path: path)
        }
        do {
            try FileManager.default.createDirectory(
                at: URL(filePath: path).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(atPath: path)
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.unix(path: path)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { connection in
                Task { @MainActor in self.serve(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            throw StartError.listenFailed(error.localizedDescription)
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        try? FileManager.default.removeItem(atPath: path)
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveLine(connection, buffer: Data())
    }

    private func receiveLine(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, isComplete, error in
            Task { @MainActor in
                var buffer = buffer
                if let data { buffer.append(data) }
                if buffer.contains(UInt8(ascii: "\n")) || isComplete || error != nil {
                    self.respond(connection, requestData: buffer)
                } else {
                    self.receiveLine(connection, buffer: buffer)
                }
            }
        }
    }

    private func respond(_ connection: NWConnection, requestData: Data) {
        Task { @MainActor in
            let response: ControlResponse
            if let newline = requestData.firstIndex(of: UInt8(ascii: "\n")),
               let request = try? JSONDecoder().decode(ControlRequest.self, from: requestData[..<newline]) {
                response = await handle(request)
            } else {
                response = .error("malformed request")
            }
            var payload = (try? JSONEncoder().encode(response)) ?? Data("{}".utf8)
            payload.append(UInt8(ascii: "\n"))
            connection.send(content: payload, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
