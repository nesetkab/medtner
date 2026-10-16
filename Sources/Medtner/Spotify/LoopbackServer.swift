import Foundation
import Network

final class LoopbackServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "medtner.loopback")

    func waitForCode(port: UInt16, path: String) async throws -> URLComponents {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        self.listener = listener

        let queue = queue
        return try await withCheckedThrowingContinuation { continuation in
            let finish = Once(continuation)
            listener.newConnectionHandler = { connection in
                connection.start(queue: queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                    guard
                        let data,
                        let request = String(data: data, encoding: .utf8),
                        let line = request.split(separator: "\r\n").first,
                        let target = line.split(separator: " ").dropFirst().first,
                        let components = URLComponents(string: "http://127.0.0.1\(target)"),
                        components.path == path
                    else {
                        connection.cancel()
                        return
                    }
                    let body = """
                    <html><body style="background:#111;color:#fff;font:600 28px -apple-system;display:grid;place-items:center;height:100vh;margin:0">
                    <div>Medtner is connected. You can close this tab.</div></body></html>
                    """
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                    listener.cancel()
                    finish(.success(components))
                }
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .failed(let error): finish(.failure(error))
                case .cancelled: finish(.failure(CancellationError()))
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func cancel() {
        listener?.cancel()
    }
}

private final class Once: @unchecked Sendable {
    private var continuation: CheckedContinuation<URLComponents, Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<URLComponents, Error>) {
        self.continuation = continuation
    }

    func callAsFunction(_ result: Result<URLComponents, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
