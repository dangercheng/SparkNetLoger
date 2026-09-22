import Foundation
import Glider

/// No build-configuration checks: the host explicitly opts in through configure(enabled:).
public enum SparkNetLoger {
    public static func configure(enabled: Bool) { Engine.shared.configure(enabled) }
    public static func startLiveLogging() { onMain { LiveService.shared.setRequested(true) } }
    public static func stopLiveLogging() { onMain { LiveService.shared.setRequested(false) } }
    public static var state: SparkNetLogerState {
        if Thread.isMainThread { return LiveService.shared.state }
        return DispatchQueue.main.sync { LiveService.shared.state }
    }
    /// Delivered on main. Keep the token for as long as updates are required.
    public static func observeState(_ callback: @escaping (SparkNetLogerState) -> Void) -> SparkNetLogerObservation {
        let id = UUID()
        onMain { LiveService.shared.observers[id] = callback; callback(LiveService.shared.state) }
        return SparkNetLogerObservation { onMain { LiveService.shared.observers.removeValue(forKey: id) } }
    }
    public static func error(_ tag: String, _ message: @autoclosure () -> String, context: [String: Any] = [:], file: String = #fileID, line: UInt = #line) {
        Engine.shared.write(.error, tag, message, context, file: file, line: line)
    }
    public static func warning(_ tag: String, _ message: @autoclosure () -> String, context: [String: Any] = [:], file: String = #fileID, line: UInt = #line) {
        Engine.shared.write(.warning, tag, message, context, file: file, line: line)
    }
    public static func info(_ tag: String, _ message: @autoclosure () -> String, context: [String: Any] = [:], file: String = #fileID, line: UInt = #line) {
        Engine.shared.write(.info, tag, message, context, file: file, line: line)
    }
    public static func debug(_ tag: String, _ message: @autoclosure () -> String, context: [String: Any] = [:], file: String = #fileID, line: UInt = #line) {
        Engine.shared.write(.debug, tag, message, context, file: file, line: line)
    }
}

public final class SparkNetLogerObservation {
    private var cancelBlock: (() -> Void)?
    internal init(_ block: @escaping () -> Void) { cancelBlock = block }
    public func cancel() { cancelBlock?(); cancelBlock = nil }
    deinit { cancel() }
}

internal func onMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
}

internal final class Engine {
    static let shared = Engine()
    private let lock = NSRecursiveLock()
    private var enabled = false
    private var generation = 0
    private let ingestion = DispatchQueue(label: "SparkNetLoger.ingestion")
    private lazy var transport = CaptureTransport(engine: self)
    private lazy var logger = Log {
        $0.subsystem = "SparkNetLoger"; $0.category = "app"; $0.level = .debug
        $0.isSynchronous = true; $0.transports = [transport]
    }
    func configure(_ value: Bool) {
        lock.lock()
        if enabled != value { generation += 1 }
        enabled = value
        let token = generation
        lock.unlock()
        onMain { [self] in
            guard currentGeneration == token else { return }
            LiveService.shared.configure(value)
        }
    }
    var currentGeneration: Int { lock.lock(); defer { lock.unlock() }; return generation }
    func accepts(_ token: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return enabled && generation == token }
    func write(_ level: LogLevel, _ tag: String, _ message: () -> String, _ context: [String: Any], file: String, line: UInt) {
        lock.lock(); let token = generation; let allowed = enabled; lock.unlock()
        guard allowed else { return }
        let record = LogRecord(level: level, tag: tag, message: message(), context: context, file: file, line: line)
        ingestion.async { [self] in
            guard accepts(token) else { return }
            var event = Event(message: Message(stringLiteral: record.json), tags: ["generation": String(token)], scope: Scope())
            logger[level.glider]?.write(event: &event, function: "", filePath: "", fileLine: 0)
        }
    }
    func capture(_ event: Event, console: ConsoleTransport) -> Bool {
        guard let raw = event.tags?["generation"], let token = Int(raw) else { return false }
        lock.lock()
        guard enabled && generation == token else { lock.unlock(); return false }
        _ = console.record(event: event)
        lock.unlock()
        guard let object = Wire.decode(event.message.content) else { return false }
        DispatchQueue.main.async { [self] in
            guard accepts(token) else { return }
            LiveService.shared.record(object)
        }
        return true
    }
}

internal final class CaptureTransport: Transport {
    let queue = DispatchQueue(label: "SparkNetLoger.capture")
    var isEnabled = true
    var minimumAcceptedLevel: Level?
    private unowned let engine: Engine
    private let console = ConsoleTransport { $0.formatters = [ConsoleFormatter()] }
    init(engine: Engine) { self.engine = engine }
    func record(event: Event) -> Bool { engine.capture(event, console: console) }
}
