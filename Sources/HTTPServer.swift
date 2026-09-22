import Foundation
import Network

internal final class HTTPServer {
    private let parameters: NWParameters
    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]
    private let resources: [String: (String, Data)]
    var configuration: () -> [String: Any] = { [:] }
    var onReady: ((UInt16) -> Void)?
    var onFailure: ((Error) -> Void)?
    var onPortConflict: ((UInt16) -> Void)?

    init(parameters: NWParameters? = nil) throws {
        let selected = parameters ?? NWParameters.tcp
        if parameters == nil { selected.requiredInterfaceType = .wifi }
        self.parameters = selected
        guard let url = Bundle(for: ResourceAnchor.self).url(forResource: "SparkNetLoger", withExtension: "bundle"),
              let bundle = Bundle(url: url) else { throw ServerError.resources }
        var files: [String: (String, Data)] = [:]
        for (path, name, ext, mime) in [
            ("/", "index", "html", "text/html; charset=utf-8"),
            ("/app.js", "app", "js", "application/javascript; charset=utf-8"),
            ("/style.css", "style", "css", "text/css; charset=utf-8"),
            ("/web_logo.png", "web_logo", "png", "image/png")
        ] {
            guard let file = bundle.url(forResource: name, withExtension: ext, subdirectory: "Web")
                    ?? bundle.url(forResource: name, withExtension: ext) else { throw ServerError.resources }
            files[path] = (mime, try Data(contentsOf: file))
        }
        resources = files
    }
    func start() throws {
        try start(on: 8848)
    }
    private func start(on port: NWEndpoint.Port) throws {
        let listener: NWListener
        do { listener = try NWListener(using: parameters, on: port) }
        catch {
            if port == 8848, let error = error as? NWError, case .posix(.EADDRINUSE) = error {
                try start(on: .any)
                onPortConflict?(8848)
                return
            }
            throw error
        }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self = self, self.listener === listener else { return }
            switch state {
            case .ready: if let port = listener?.port { self.onReady?(port.rawValue) }
            case .waiting(let error), .failed(let error):
                if port == 8848, case .posix(.EADDRINUSE) = error {
                    // A bind conflict may arrive as waiting or failed. Retire this
                    // listener before retrying so stale callbacks cannot restart it.
                    listener?.stateUpdateHandler = nil
                    listener?.newConnectionHandler = nil
                    listener?.cancel()
                    self.listener = nil
                    do {
                        try self.start(on: .any)
                        self.onPortConflict?(8848)
                    } catch { self.onFailure?(error) }
                } else if case .failed = state { self.onFailure?(error) }
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: .main)
    }
    func stop() {
        listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil
        listener?.cancel(); listener = nil
        let connections = Array(clients.values); clients.removeAll()
        connections.forEach { $0.stateUpdateHandler = nil; $0.cancel() }
    }
    private func accept(_ connection: NWConnection) {
        guard clients.count < 32 else { connection.cancel(); return }
        let id = UUID(); clients[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.close(id) }
            if case .cancelled = state { self?.close(id) }
        }
        connection.start(queue: .main)
        read(id, buffer: Data())
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.close(id) }
    }
    private func read(_ id: UUID, buffer: Data) {
        guard let connection = clients[id] else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self = self, self.clients[id] != nil else { return }
            var input = buffer; input.append(data ?? Data())
            if input.count > 16384 { self.respond(id, code: 431, mime: "text/plain", body: Data()); return }
            if input.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.route(id, input: input)
            } else if complete || error != nil { self.close(id) }
            else { self.read(id, buffer: input) }
        }
    }
    private func route(_ id: UUID, input: Data) {
        guard let text = String(data: input, encoding: .utf8),
              let line = text.components(separatedBy: "\r\n").first else { close(id); return }
        let parts = line.split(separator: " ")
        guard parts.count == 3 else { respond(id, code: 400, mime: "text/plain", body: Data()); return }
        guard parts[0] == "GET" else { respond(id, code: 405, mime: "text/plain", body: Data()); return }
        let path = String(parts[1].split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])
        if path == "/config.json" {
            respond(id, code: 200, mime: "application/json", body: Data(Wire.encode(configuration()).utf8))
        } else if let (mime, body) = resources[path] {
            respond(id, code: 200, mime: mime, body: body)
        } else { respond(id, code: 404, mime: "text/plain", body: Data("Not Found".utf8)) }
    }
    private func respond(_ id: UUID, code: Int, mime: String, body: Data) {
        guard let connection = clients[id] else { return }
        let reason = code == 200 ? "OK" : "Error"
        var output = Data("HTTP/1.1 \(code) \(reason)\r\nContent-Type: \(mime)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'self'; connect-src 'self' ws:; style-src 'self'; script-src 'self'; object-src 'none'; frame-ancestors 'none'\r\nConnection: close\r\n\r\n".utf8)
        output.append(body)
        connection.send(content: output, completion: .contentProcessed { [weak self] _ in self?.close(id) })
    }
    private func close(_ id: UUID) {
        let connection = clients.removeValue(forKey: id)
        connection?.stateUpdateHandler = nil; connection?.cancel()
    }
    enum ServerError: LocalizedError {
        case resources
        var errorDescription: String? { L10n.text("resources") }
    }
}
private final class ResourceAnchor: NSObject {}
