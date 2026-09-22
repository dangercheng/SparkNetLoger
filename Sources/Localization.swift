import Foundation

/// Built-in UI translations are independent of the host app resource bundle.
internal enum L10n {
    static let strings: [String: [String: String]] = [
        "title": ["en": "Live Logs", "zh": "实时日志"],
        "heading": ["en": "LAN Live Logs", "zh": "局域网实时日志"],
        "note": ["en": "Open the address below in a browser on the same Wi-Fi. Logging pauses in the background and resumes in the foreground. Your switch preference is saved for the next launch.", "zh": "在同一 Wi-Fi 的浏览器中打开下方地址。App 进入后台时暂停服务，返回前台后自动恢复。开关选择会在下次启动时恢复。"],
        "copyAddress": ["en": "Copy Web Address", "zh": "复制网页地址"],
        "disabled": ["en": "Logging is disabled by the host app", "zh": "接入方尚未启用日志库"],
        "off": ["en": "Off", "zh": "已关闭"],
        "waiting": ["en": "Waiting for Wi-Fi", "zh": "等待 Wi-Fi 网络"],
        "starting": ["en": "Starting service…", "zh": "正在启动服务…"],
        "running": ["en": "Service running", "zh": "服务运行中"],
        "paused": ["en": "Paused in background; resumes in foreground", "zh": "后台暂停，返回前台后恢复"],
        "failed": ["en": "Failed to start", "zh": "启动失败"],
        "addressPending": ["en": "Web address will appear when the service is ready", "zh": "服务就绪后显示网页地址"],
        "connections": ["en": "Connected browsers: %d", "zh": "已连接浏览器：%d"],
        "portChanged": ["en": "Web port 8848 is in use. Switched to %d. Use the new address below.", "zh": "网页端口 8848 已被占用，已自动切换至 %d，请使用下方新地址。"],
        "portBusy": ["en": "Web port %d is in use. Selecting an available port…", "zh": "网页端口 %d 已被占用，正在自动选择可用端口…"],
        "timeout": ["en": "Service startup timed out. Check Wi-Fi and try again.", "zh": "服务启动超时，请检查 Wi-Fi 后重新开启。"],
        "socketStopped": ["en": "WebSocket service stopped. Please enable it again.", "zh": "WebSocket 服务已停止，请重新开启。"],
        "resources": ["en": "SparkNetLoger web resources are missing. Check the Pod resource bundle.", "zh": "缺少 SparkNetLoger 网页资源，请检查 Pod 资源 Bundle。"],
        "truncated": ["en": "…[truncated]", "zh": "…[已截断]"],
        "contextTruncated": ["en": "Context exceeded 32 KiB and was truncated", "zh": "上下文超过 32 KiB，已截断"],
    ]
    static func localized(_ key: String, language: String, arguments: [CVarArg] = []) -> String {
        let code = language.lowercased().hasPrefix("zh") ? "zh" : "en"
        let format = strings[key]?[code] ?? strings[key]?["en"] ?? key
        return String(format: format, arguments: arguments)
    }
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        localized(key, language: Locale.preferredLanguages.first ?? "en", arguments: arguments)
    }
}
