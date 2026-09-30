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

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: self?.queue ?? .main)
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
                    if !finished {
                        finished = true
                        listener.cancel()
                        continuation.resume(returning: components)
                    }
                }
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state, !finished {
                    finished = true
                    continuation.resume(throwing: error)
                }
            }
            listener.start(queue: queue)
        }
    }

    func cancel() {
        listener?.cancel()
    }
}
