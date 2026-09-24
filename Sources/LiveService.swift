import Foundation
import UIKit
import Network
import Glider
import Darwin

public struct SparkNetLogerState {
    /// `paused` is retained for source compatibility; backgrounding no longer emits it.
    public enum Phase: String { case disabled, off, waitingForWiFi, starting, running, paused, failed }
    public let phase: Phase
    public let enabled: Bool
    public let liveLoggingRequested: Bool
    public let webURL: URL?
    public let connectionCount: Int
    public let errorMessage: String?
    /// Nonfatal startup notice, such as an automatic HTTP port change.
    public let noticeMessage: String?
}

internal final class LiveService: NSObject {
    static let shared = LiveService()
    static let preferenceKey = "SparkNetLoger.liveLoggingRequested.v1"
    var observers: [UUID: (SparkNetLogerState) -> Void] = [:]
    private(set) var state: SparkNetLogerState
    private let defaults: UserDefaults
    private let requiresWiFi: Bool
    private let addressProvider: (NWPath) -> String?
    private var enabled = false
    private var requested: Bool
    private var monitor: NWPathMonitor?
    private var path: NWPath?
    private var address: String?
    private var http: HTTPServer?
    private var socket: WebSocketTransportServer?
    private var socketAcceptedPeer = false
    private var socketReady = false
    private var httpPort: UInt16?
    private var portNotice: String?
    private var socketPort: UInt16 = 49152
    private var peers: [Int: WebSocketPeer] = [:]
    private var token = UUID()
    private var session = UUID().uuidString
    private var sequence = 0
    private var history = LogHistory()
    private var pending: [[String: Any]] = []
    private var flushScheduled = false

    init(defaults: UserDefaults = .standard, requiresWiFi: Bool = true,
         addressProvider: ((NWPath) -> String?)? = nil) {
        self.defaults = defaults
        self.requiresWiFi = requiresWiFi
        self.addressProvider = addressProvider ?? Self.wifiAddress
        requested = defaults.bool(forKey: Self.preferenceKey)
        state = SparkNetLogerState(phase: .disabled, enabled: false,
            liveLoggingRequested: requested, webURL: nil, connectionCount: 0, errorMessage: nil, noticeMessage: nil)
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(active), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    func configure(_ value: Bool) {
        enabled = value
        if value { startMonitor(); reconcile() }
        else {
            monitor?.cancel(); monitor = nil; path = nil
            shutdown(permanent: true); resetHistory(); publish(.disabled)
        }
    }
    func setRequested(_ value: Bool) {
        let changed = requested != value
        requested = value
        defaults.set(value, forKey: Self.preferenceKey)
        if !value { shutdown(permanent: true); resetHistory() }
        else if changed { resetHistory() }
        reconcile()
    }
    private func resetHistory() { history.clear(); pending.removeAll(); session = UUID().uuidString; sequence = 0 }
    private func startMonitor() {
        guard monitor == nil else { return }
        let monitor = requiresWiFi ? NWPathMonitor(requiredInterfaceType: .wifi) : NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self, weak monitor] path in
            guard let self = self, self.monitor === monitor else { return }
            self.path = path; self.reconcile()
        }
        monitor.start(queue: .main)
    }
    // Recheck network/service failures on return without replacing healthy connections.
    @objc private func active() { reconcile() }

    private func reconcile() {
        guard enabled else { publish(.disabled); return }
        guard requested else { publish(.off); return }
        guard let path = path, path.status == .satisfied,
              let host = addressProvider(path) else {
            shutdown(permanent: false); publish(.waitingForWiFi); return
        }
        if address != host { shutdown(permanent: false) }
        address = host
        if http != nil && socket != nil { announceIfReady(); return }
        startServers()
    }
    private func startServers() {
        token = UUID(); let current = token
        socketReady = false; httpPort = nil; portNotice = nil; publish(.starting)
        do {
            let server = try HTTPServer(parameters: requiresWiFi ? nil : .tcp); http = server
            server.configuration = { [weak self] in
                guard let self = self else { return [:] }
                return ["version": 1, "webSocketPort": self.socketPort, "sessionID": self.session]
            }
            server.onReady = { [weak self] port in
                guard let self = self, self.token == current else { return }
                if self.portNotice != nil {
                    self.portNotice = L10n.text("portChanged", Int(port))
                }
                self.httpPort = port; self.announceIfReady()
            }
            server.onPortConflict = { [weak self] port in
                guard let self = self, self.token == current else { return }
                self.portNotice = L10n.text("portBusy", Int(port))
                self.publish(.starting)
            }
            server.onFailure = { [weak self] error in
                guard let self = self, self.token == current else { return }; self.fail(error)
            }
            try server.start()
            try startSocket(port: 49152)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self = self, self.token == current, self.state.phase == .starting else { return }
                self.fail(NSError(domain: "SparkNetLoger", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.text("timeout")]))
            }
        } catch { fail(error) }
    }
    private func startSocket(port: UInt16) throws {
        socketPort = port
        let parameters = NWParameters(tls: nil)
        if requiresWiFi { parameters.requiredInterfaceType = .wifi }
        parameters.allowLocalEndpointReuse = true
        let server = try WebSocketTransportServer(port: port, delegate: self) {
            $0.startImmediately = false; $0.parameters = parameters
            $0.queue = .main; $0.formatters = [RawFormatter()]
        }
        socketAcceptedPeer = false
        socket = server
        try server.start()
    }
    private func announceIfReady() {
        guard socketReady, httpPort != nil else { return }
        publish(.running)
    }
    private func fail(_ error: Error) { shutdown(permanent: false); publish(.failed, error: error.localizedDescription) }
    private func shutdown(permanent: Bool) {
        token = UUID()
        let control = Wire.envelope(permanent ? "closed" : "suspended", session: session)
        peers.values.forEach { $0.send(string: control) }
        if socketAcceptedPeer, let socket = socket { RetiredGliderServers.keep(socket) }
        socket?.delegate = nil; socket?.isEnabled = false; socket?.stop(); socket = nil
        socketAcceptedPeer = false
        http?.stop(); http = nil
        peers.removeAll(); socketReady = false; httpPort = nil; portNotice = nil; address = nil
        pending.removeAll(); flushScheduled = false
    }
    private func publish(_ phase: SparkNetLogerState.Phase, error: String? = nil) {
        var url: URL?
        if phase == .running, let address = address, let port = httpPort {
            let host = address.contains(":") ? "[\(address)]" : address
            url = URL(string: "http://\(host):\(port)/")
        }
        state = SparkNetLogerState(phase: phase, enabled: enabled, liveLoggingRequested: requested,
            webURL: url, connectionCount: peers.count, errorMessage: error, noticeMessage: portNotice)
        Array(observers.values).forEach { $0(state) }
    }
    func record(_ object: [String: Any]) {
        guard enabled && requested else { return }
        sequence += 1
        var entry = object
        entry["sequence"] = sequence; entry["sessionID"] = session; entry["version"] = 1
        history.append(entry)
        guard socketReady else { return }
        if pending.count == 2000 { flush() }
        pending.append(entry)
        guard !flushScheduled else { return }
        flushScheduled = true; let current = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, self.token == current else { return }
            self.flushScheduled = false; self.flush()
        }
    }
    private func flush() {
        guard socketReady, let socket = socket, !pending.isEmpty else { return }
        // Small frames instead of one multi-megabyte history/broadcast frame.
        while !pending.isEmpty {
            let entries = Array(pending.prefix(20)); pending.removeFirst(entries.count)
            let text = Wire.envelope("logs", session: session, extra: ["entries": entries])
            _ = socket.record(event: Event(message: Message(stringLiteral: text), scope: Scope()))
        }
    }
    private func sendHistory(_ peer: WebSocketPeer) {
        peer.send(string: Wire.envelope("historyStart", session: session))
        let values = history.values
        for start in stride(from: 0, to: values.count, by: 20) {
            peer.send(string: Wire.envelope("logs", session: session,
                extra: ["entries": Array(values[start..<min(start + 20, values.count)])]))
        }
        peer.send(string: Wire.envelope("historyEnd", session: session))
    }
    private static func wifiAddress(_ path: NWPath) -> String? {
        let names = Set(path.availableInterfaces.filter { $0.type == .wifi }.map { $0.name })
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }; defer { freeifaddrs(list) }
        var current = list; var ipv6: String?
        while let node = current {
            defer { current = node.pointee.ifa_next }
            guard names.contains(String(cString: node.pointee.ifa_name)),
                  let addr = node.pointee.ifa_addr else { continue }
            let family = Int32(addr.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let value = String(cString: host)
            if family == AF_INET { return value }
            if !value.hasPrefix("fe80:") { ipv6 = value }
        }
        return ipv6
    }
}

extension LiveService: WebSocketTransportServerDelegate {
    func webSocketServerTransport(_ transport: WebSocketTransportServer, didChangeState state: NWListener.State) {
        onMain { [weak self] in
            guard let self = self, self.socket === transport else { return }
            switch state {
            case .ready: self.socketReady = true; self.announceIfReady()
            case .failed(let error): self.fail(error)
            default: break
            }
        }
    }
    func webSocketServerTransport(_ transport: WebSocketTransportServer, didDisconnect error: NWError?) {
        onMain { [weak self] in
            guard let self = self, self.socket === transport else { return }
            if let error = error, case .posix(.EADDRINUSE) = error, self.socketPort < 49251 {
                transport.delegate = nil; self.socket = nil
                do { try self.startSocket(port: self.socketPort + 1) } catch { self.fail(error) }
            } else {
                self.fail(error ?? NSError(domain: "SparkNetLoger", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: L10n.text("socketStopped")]))
            }
        }
    }
    func webSocketServerTransport(_ transport: WebSocketTransportServer, peer: WebSocketPeer, didChangeState state: NWConnection.State) {
        onMain { [weak self] in
            guard let self = self, self.socket === transport else { return }
            switch state {
            case .ready:
                if self.peers[peer.id] == nil { self.peers[peer.id] = peer; self.sendHistory(peer) }
            case .failed, .cancelled: self.peers.removeValue(forKey: peer.id)
            default: break
            }
            if self.socketReady { self.announceIfReady() }
        }
    }
    func webSocketServerTransport(_ transport: WebSocketTransportServer, didDisconnectPeer peer: WebSocketPeer) {
        onMain { [weak self] in
            guard let self = self, self.socket === transport else { return }
            self.peers.removeValue(forKey: peer.id); self.announceIfReady()
        }
    }
    func webSocketServerTransport(_ transport: WebSocketTransportServer, didReceiveError error: Error?) {}
    func webSocketServerTransport(_ transport: WebSocketTransportServer, didConnectPeer peer: WebSocketPeer) {
        onMain { [weak self] in
            guard let self = self, self.socket === transport else { return }
            self.socketAcceptedPeer = true
        }
    }
    func webSocketServerTransport(_ transport: WebSocketTransportServer, didStartBonjour identifier: String, name: String) {}
    func webSocketServerTransport(_ transport: WebSocketTransportServer, didStopBonjour error: Error?) {}
    func webSocketServerTransport(_ transport: WebSocketTransportServer, didReceiveData data: Data, fromPeer peer: WebSocketPeer) {}
    func webSocketServerTransport(_ transport: WebSocketTransportServer, didReceiveString string: String, fromPeer peer: WebSocketPeer) {}
}

/// Glider's peer stop() is empty and its callbacks capture the server unowned.
/// Keep servers that accepted peers alive until process exit: stopping the listener
/// alone does not make it safe to deallocate them. Must only be accessed on main.
internal enum RetiredGliderServers {
    private static var servers: [WebSocketTransportServer] = []
    static func keep(_ server: WebSocketTransportServer) { servers.append(server) }
}
