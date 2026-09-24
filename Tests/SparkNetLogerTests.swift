import XCTest
import Glider
import Network
import UIKit
@testable import SparkNetLoger

final class SparkNetLogerTests: XCTestCase {



    func testFullLiveServiceHistoryBroadcastAndPersistentRestart() {
        let suite = "SparkNetLogerTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var service: LiveService!
        let running = expectation(description: "service running")
        let observer = UUID()
        DispatchQueue.main.async {
            service = LiveService(defaults: defaults, requiresWiFi: false, addressProvider: { _ in "127.0.0.1" })
            service.observers[observer] = { state in
                if state.phase == .running { service.observers.removeValue(forKey: observer); running.fulfill() }
                if state.phase == .failed { XCTFail(state.errorMessage ?? "failed") }
            }
            service.configure(true); service.setRequested(true)
            service.record(LogRecord(level: .info, tag: "History", message: "before-connect", context: [:]).object)
        }
        wait(for: [running], timeout: 10)
        var webURL: URL?
        let captured = expectation(description: "URL captured")
        DispatchQueue.main.async { webURL = service.state.webURL; captured.fulfill() }
        wait(for: [captured], timeout: 2)
        guard let url = webURL else { XCTFail("No URL"); return }
        let configReady = expectation(description: "config")
        var socketPort: Int = 0
        URLSession.shared.dataTask(with: url.appendingPathComponent("config.json")) { data, _, error in
            XCTAssertNil(error)
            if let data = data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                socketPort = object["webSocketPort"] as? Int ?? 0
            }
            configReady.fulfill()
        }.resume()
        wait(for: [configReady], timeout: 5)
        guard socketPort > 0 else { XCTFail("No WebSocket port"); return }
        let client = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(socketPort)")!)
        let history = expectation(description: "history synchronization")
        let live = expectation(description: "live broadcast")
        let closed = expectation(description: "close notice")
        var sawHistory = false
        var sawLive = false
        var sawEnd = false
        func receive() {
            client.receive { result in
                guard case .success(.string(let text)) = result, let packet = Wire.decode(text) else { return }
                let type = packet["type"] as? String
                if type == "logs", let entries = packet["entries"] as? [[String: Any]] {
                    for entry in entries {
                        if entry["message"] as? String == "before-connect" { sawHistory = true }
                        if entry["message"] as? String == "after-connect", !sawLive { sawLive = true; live.fulfill() }
                    }
                }
                if type == "historyEnd", !sawEnd { sawEnd = true; history.fulfill() }
                if type == "closed" { closed.fulfill(); return }
                receive()
            }
        }
        client.resume(); receive()
        wait(for: [history], timeout: 5); XCTAssertTrue(sawHistory)
        let backgroundHTTP = expectation(description: "HTTP remains available after background notification")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            XCTAssertEqual(service.state.phase, .running)
            XCTAssertEqual(service.state.webURL, url)
            XCTAssertEqual(service.state.connectionCount, 1)
            service.record(LogRecord(level: .debug, tag: "Live", message: "after-connect", context: ["ok": true]).object)
            URLSession.shared.dataTask(with: url.appendingPathComponent("config.json")) { data, response, error in
                XCTAssertNil(error)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
                let config = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                XCTAssertEqual(config?["webSocketPort"] as? Int, socketPort)
                backgroundHTTP.fulfill()
            }.resume()
        }
        // The existing client must receive the live log without reconnecting.
        // Synthetic lifecycle notifications do not simulate OS process suspension.
        wait(for: [live, backgroundHTTP], timeout: 5)
        let foreground = expectation(description: "foreground preserves connection")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
            XCTAssertEqual(service.state.phase, .running)
            XCTAssertEqual(service.state.webURL, url)
            XCTAssertEqual(service.state.connectionCount, 1)
            foreground.fulfill()
        }
        wait(for: [foreground], timeout: 2)
        DispatchQueue.main.async { service.setRequested(false) }
        wait(for: [closed], timeout: 5)
        client.cancel(with: .normalClosure, reason: nil)
        let restarted = expectation(description: "persistent restore")
        DispatchQueue.main.async {
            XCTAssertNil(service.state.webURL)
            XCTAssertFalse(defaults.bool(forKey: LiveService.preferenceKey))
            service.setRequested(true)
            service.configure(false)
            XCTAssertTrue(defaults.bool(forKey: LiveService.preferenceKey))
            // A new manager models a fresh process restoring UserDefaults.
            service = LiveService(defaults: defaults, requiresWiFi: false, addressProvider: { _ in "127.0.0.1" })
            service.observers[observer] = { state in
                if state.phase == .running {
                    service.observers.removeValue(forKey: observer)
                    service.setRequested(false); service.configure(false); restarted.fulfill()
                }
            }
            service.configure(true)
        }
        wait(for: [restarted], timeout: 10)
    }

    func testNativeGliderWebSocketRoundTrip() {
        let ready = expectation(description: "native listener")
        let received = expectation(description: "native transport received")
        let stopped = expectation(description: "native listener stopped")
        let delegate = SocketProbe()
        let port = UInt16.random(in: 55000...60000)
        var transport: WebSocketTransportServer!
        delegate.listenerState = { state in
            if case .ready = state { ready.fulfill() }
            if case .cancelled = state { stopped.fulfill() }
            if case .failed(let error) = state { XCTFail(error.localizedDescription) }
        }
        DispatchQueue.main.async {
            do {
                transport = try WebSocketTransportServer(port: port, delegate: delegate) {
                    $0.startImmediately = false; $0.formatters = [RawFormatter()]; $0.queue = .main
                }
                try transport.start()
            } catch { XCTFail(error.localizedDescription); ready.fulfill() }
        }
        wait(for: [ready], timeout: 5)
        let client = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)")!)
        delegate.peerReady = {
            DispatchQueue.main.async {
                let payload = Wire.envelope("logs", session: "test", extra: ["entries": [["message": "你好 🌍"]]])
                _ = transport.record(event: Event(message: Message(stringLiteral: payload), scope: Scope()))
            }
        }
        client.resume()
        client.receive { result in
            switch result {
            case .success(.string(let text)):
                XCTAssertEqual(Wire.decode(text)?["type"] as? String, "logs")
                XCTAssertTrue(text.contains("你好"))
            case .success: XCTFail("Expected JSON text frame")
            case .failure(let error): XCTFail(error.localizedDescription)
            }
            received.fulfill()
        }
        wait(for: [received], timeout: 10)
        client.cancel(with: .normalClosure, reason: nil)
        DispatchQueue.main.async { RetiredGliderServers.keep(transport); transport.stop() }
        wait(for: [stopped], timeout: 5)
        withExtendedLifetime(delegate) {}
    }

    func testEnabledFacadeEvaluatesAllLevelsRegardlessOfBuildConfiguration() {
        SparkNetLoger.configure(enabled: true)
        var calls = 0
        func message() -> String { calls += 1; return "enabled message" }
        SparkNetLoger.error("Test", message()); SparkNetLoger.warning("Test", message())
        SparkNetLoger.info("Test", message()); SparkNetLoger.debug("Test", message())
        XCTAssertEqual(calls, 4)
        SparkNetLoger.configure(enabled: false)
    }

    func testHTTPPortConflictNoticeAndPreferredPortOnRestart() throws {
        let suite = "SparkNetLogerTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let blocker = try NWListener(using: .tcp, on: 8848)
        blocker.newConnectionHandler = { $0.cancel() }
        var service: LiveService!
        defer {
            let stopped = expectation(description: "cleanup conflict test")
            DispatchQueue.main.async {
                service?.configure(false); blocker.cancel(); stopped.fulfill()
            }
            wait(for: [stopped], timeout: 3)
            defaults.removePersistentDomain(forName: suite)
        }
        let occupied = expectation(description: "8848 occupied")
        blocker.stateUpdateHandler = { state in
            if case .ready = state { occupied.fulfill() }
            if case .failed(let error) = state { XCTFail(error.localizedDescription) }
        }
        blocker.start(queue: .main)
        wait(for: [occupied], timeout: 5)
        let running = expectation(description: "fallback running")
        let observer = UUID()
        var fallbackURL: URL?
        var sawConflict = false
        DispatchQueue.main.async {
            service = LiveService(defaults: defaults, requiresWiFi: false, addressProvider: { _ in "127.0.0.1" })
            service.observers[observer] = { state in
                if state.phase == .starting, state.noticeMessage == L10n.text("portBusy", 8848) {
                    sawConflict = true
                }
                if state.phase == .failed { XCTFail(state.errorMessage ?? "failed") }
                if state.phase == .running {
                    service.observers.removeValue(forKey: observer)
                    fallbackURL = state.webURL
                    XCTAssertTrue(sawConflict)
                    XCTAssertNil(state.errorMessage)
                    XCTAssertNotEqual(state.webURL?.port, 8848)
                    XCTAssertEqual(state.noticeMessage, L10n.text("portChanged", state.webURL?.port ?? 0))
                    running.fulfill()
                }
            }
            service.configure(true); service.setRequested(true)
        }
        wait(for: [running], timeout: 10)
        let url = try XCTUnwrap(fallbackURL)
        let received = expectation(description: "fallback HTTP response")
        URLSession.shared.dataTask(with: url.appendingPathComponent("config.json")) { data, response, error in
            XCTAssertNil(error)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            XCTAssertFalse(data?.isEmpty ?? true)
            received.fulfill()
        }.resume()
        wait(for: [received], timeout: 5)
        let released = expectation(description: "preferred port released")
        DispatchQueue.main.async {
            service.configure(false)
            XCTAssertNil(service.state.noticeMessage)
            blocker.stateUpdateHandler = { state in
                if case .cancelled = state { released.fulfill() }
            }
            blocker.cancel()
        }
        wait(for: [released], timeout: 5)
        let restarted = expectation(description: "restart prefers 8848")
        DispatchQueue.main.async {
            service.observers[observer] = { state in
                if state.phase == .failed { XCTFail(state.errorMessage ?? "failed") }
                if state.phase == .running {
                    service.observers.removeValue(forKey: observer)
                    XCTAssertEqual(state.webURL?.port, 8848)
                    XCTAssertNil(state.noticeMessage)
                    restarted.fulfill()
                }
            }
            service.configure(true)
        }
        wait(for: [restarted], timeout: 10)
    }

    func testHTTPResourcesConfigAndNotFound() throws {
        let ready = expectation(description: "HTTP ready")
        var server: HTTPServer!
        var port: UInt16 = 0
        DispatchQueue.main.async {
            do {
                server = try HTTPServer(parameters: .tcp)
                server.configuration = { ["version": 1, "webSocketPort": 49152] }
                server.onReady = { port = $0; ready.fulfill() }
                server.onFailure = { XCTFail($0.localizedDescription); ready.fulfill() }
                try server.start()
            } catch { XCTFail(error.localizedDescription); ready.fulfill() }
        }
        wait(for: [ready], timeout: 5)
        XCTAssertGreaterThan(port, 0)
        guard port != 0 else { return }
        let requests = ["/", "/app.js", "/style.css", "/web_logo.png", "/config.json", "/missing", "/?query=test"]
        let received = expectation(description: "resources")
        received.expectedFulfillmentCount = requests.count
        for path in requests {
            URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:\(port)\(path)")!) { data, response, error in
                XCTAssertNil(error)
                let response = response as? HTTPURLResponse
                XCTAssertEqual(response?.statusCode, path == "/missing" ? 404 : 200)
                XCTAssertFalse(data?.isEmpty ?? true)
                if path == "/web_logo.png" {
                    XCTAssertEqual(response?.mimeType, "image/png")
                    XCTAssertEqual(data?.prefix(8), Data([137, 80, 78, 71, 13, 10, 26, 10]))
                }
                if path == "/config.json" {
                    let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
                    XCTAssertEqual(json?["webSocketPort"] as? Int, 49152)
                }
                received.fulfill()
            }.resume()
        }
        wait(for: [received], timeout: 10)
        let stopped = expectation(description: "HTTP stop")
        DispatchQueue.main.async { server.stop(); server.stop(); stopped.fulfill() }
        wait(for: [stopped], timeout: 3)
    }

    func testUnicodeAndContextBounds() {
        let text = LogSnapshot.text(String(repeating: "😀汉字", count: 10000))
        XCTAssertLessThanOrEqual(text.utf8.count, 32768)
        XCTAssertTrue(text.hasSuffix(LogSnapshot.marker))
        let value = LogSnapshot.context(["large": String(repeating: "汉", count: 50000)])
        XCTAssertLessThanOrEqual(try! JSONSerialization.data(withJSONObject: value).count, 32768)
    }
    func testContextSnapshotAndConversion() {
        let mutable = NSMutableString(string: "before")
        let snapshot = LogSnapshot.context(["text": mutable, "bool": true, "null": NSNull(),
            "date": Date(timeIntervalSince1970: 0), "url": URL(string: "https://example.com")!,
            "nested": ["values": [1, 2, 3]], "nan": Double.nan])
        mutable.setString("after")
        XCTAssertEqual(snapshot["text"] as? String, "before")
        XCTAssertEqual(snapshot["bool"] as? Bool, true)
        XCTAssertEqual(snapshot["date"] as? String, "1970-01-01T00:00:00Z")
        XCTAssertEqual(snapshot["url"] as? String, "https://example.com")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(snapshot))
    }
    func testDepthLimit() {
        var value: [String: Any] = ["secret": "leaf"]
        for _ in 0..<20 { value = ["nested": value] }
        let result = Wire.encode(LogSnapshot.context(value))
        XCTAssertTrue(result.contains(LogSnapshot.marker)); XCTAssertFalse(result.contains("leaf"))
    }
    func testWireContainsOnlyContractFields() {
        let record = LogRecord(level: .error, tag: " ", message: "body", context: ["statusCode": 500], file: "/project/Player.swift", line: 42)
        XCTAssertEqual(Set(record.object.keys), Set(["timestamp", "level", "tag", "message", "context", "file", "line"]))
        XCTAssertEqual(record.tag, "Default")
        XCTAssertEqual(record.file, "Player.swift")
        XCTAssertEqual(record.line, 42)
        let formatted = ConsoleFormatter().format(event: Event(message: Message(stringLiteral: record.json)))?.asString()
        XCTAssertTrue(formatted?.contains("500") == true)
        XCTAssertTrue(formatted?.contains("[Player.swift:42]") == true)
        XCTAssertFalse(record.json.contains("/project/"))
        for key in ["filePath", "fileLine", "function"] { XCTAssertFalse(record.json.contains(key)) }
    }
    func testEnglishAndChineseLocalization() {
        for key in L10n.strings.keys {
            XCTAssertNotNil(L10n.strings[key]?["en"])
            XCTAssertNotNil(L10n.strings[key]?["zh"])
            XCTAssertFalse(L10n.localized(key, language: "en", arguments: [1]).isEmpty)
            XCTAssertFalse(L10n.localized(key, language: "zh-Hans", arguments: [1]).isEmpty)
        }
        XCTAssertEqual(L10n.localized("title", language: "en-US"), "Live Logs")
        XCTAssertEqual(L10n.localized("title", language: "zh-Hant"), "实时日志")
        XCTAssertEqual(L10n.localized("title", language: "fr"), "Live Logs")
        XCTAssertEqual(L10n.localized("connections", language: "en", arguments: [3]), "Connected browsers: 3")
        XCTAssertEqual(L10n.localized("connections", language: "zh", arguments: [3]), "已连接浏览器：3")
        XCTAssertTrue(L10n.localized("portChanged", language: "en", arguments: [54321]).contains("54321"))
        XCTAssertTrue(L10n.localized("portChanged", language: "zh", arguments: [54321]).contains("54321"))
    }
    func testRecordCapturesCallerLocationByDefault() {
        let expectedLine = #line + 1
        let record = LogRecord(level: .info, tag: "Test", message: "caller", context: [:])
        XCTAssertEqual(record.file, "SparkNetLogerTests.swift")
        XCTAssertEqual(record.line, UInt(expectedLine))
    }
    func testHistoryWraparoundAndClear() {
        var history = LogHistory(capacity: 3)
        for id in 0..<10 { history.append(["sequence": id]) }
        XCTAssertEqual(history.values.compactMap { $0["sequence"] as? Int }, [7, 8, 9])
        history.clear(); XCTAssertTrue(history.values.isEmpty)
        history.append(["sequence": 10]); XCTAssertEqual(history.values.count, 1)
    }
    func testDisabledFacadeDoesNotEvaluateMessage() {
        SparkNetLoger.configure(enabled: false)
        var evaluated = 0
        func message() -> String { evaluated += 1; return "unused" }
        SparkNetLoger.error("Test", message()); SparkNetLoger.warning("Test", message())
        SparkNetLoger.info("Test", message()); SparkNetLoger.debug("Test", message())
        XCTAssertEqual(evaluated, 0)
    }
    func testPreferenceSurvivesGlobalDisable() {
        let done = expectation(description: "main state")
        DispatchQueue.main.async {
            let old = UserDefaults.standard.object(forKey: LiveService.preferenceKey)
            SparkNetLoger.configure(enabled: false)
            SparkNetLoger.startLiveLogging()
            XCTAssertTrue(UserDefaults.standard.bool(forKey: LiveService.preferenceKey))
            SparkNetLoger.configure(enabled: false)
            XCTAssertTrue(UserDefaults.standard.bool(forKey: LiveService.preferenceKey))
            XCTAssertEqual(SparkNetLoger.state.phase, .disabled)
            XCTAssertNil(SparkNetLoger.state.webURL)
            SparkNetLoger.stopLiveLogging()
            XCTAssertFalse(UserDefaults.standard.bool(forKey: LiveService.preferenceKey))
            UserDefaults.standard.set(old, forKey: LiveService.preferenceKey)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }
}

private final class SocketProbe: WebSocketTransportServerDelegate {
    var listenerState: ((NWListener.State) -> Void)?
    var peerReady: (() -> Void)?
    func webSocketServerTransport(_ transport: WebSocketTransportServer, didChangeState state: NWListener.State) { listenerState?(state) }
    func webSocketServerTransport(_ transport: WebSocketTransportServer, peer: WebSocketPeer, didChangeState state: NWConnection.State) {
        if case .ready = state { peerReady?() }
    }
    func webSocketServerTransport(_ transport: WebSocketTransportServer, didStartBonjour identifier: String, name: String) {}
    func webSocketServerTransport(_ transport: WebSocketTransportServer, didStopBonjour error: Error?) {}
    func webSocketServerTransport(_ transport: WebSocketTransportServer, didReceiveError error: Error?) {}
    func webSocketServerTransport(_ transport: WebSocketTransportServer, didDisconnectPeer peer: WebSocketPeer) {}
    func webSocketServerTransport(_ transport: WebSocketTransportServer, didDisconnect error: NWError?) {}
    func webSocketServerTransport(_ transport: WebSocketTransportServer, didConnectPeer peer: WebSocketPeer) {}
    func webSocketServerTransport(_ transport: WebSocketTransportServer, didReceiveData data: Data, fromPeer peer: WebSocketPeer) {}
    func webSocketServerTransport(_ transport: WebSocketTransportServer, didReceiveString string: String, fromPeer peer: WebSocketPeer) {}
}
