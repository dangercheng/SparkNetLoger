import UIKit
import SparkNetLoger

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if DEBUG
        SparkNetLoger.configure(enabled: true)
        #else
        SparkNetLoger.configure(enabled: false)
        #endif
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: DemoViewController())
        window.makeKeyAndVisible(); self.window = window
        return true
    }
}

final class DemoViewController: UIViewController {
    private var timer: Timer?
    private var sequence = 0
    override func viewDidLoad() {
        super.viewDidLoad(); title = "SparkNetLoger Demo"; view.backgroundColor = .systemBackground
        let intro = UILabel(); intro.numberOfLines = 0
        intro.text = demoText("Enable live logs in Settings, then open the displayed address in a browser on the same Wi-Fi.\n\nYou can disconnect the USB cable.", "在设置中开启实时日志，然后用同一 Wi-Fi 的浏览器打开手机显示的地址。\n\n可拔掉数据线进行测试。")
        let stack = UIStackView(arrangedSubviews: [intro]); stack.axis = .vertical; stack.spacing = 20
        #if DEBUG
        let settings = UIButton(type: .system); settings.setTitle(demoText("Settings · Live Logs", "设置 · 实时日志"), for: .normal)
        settings.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        stack.addArrangedSubview(settings)
        #endif
        let emit = UIButton(type: .system); emit.setTitle(demoText("Emit all four log levels", "输出四种等级日志"), for: .normal)
        emit.addTarget(self, action: #selector(emitLogs), for: .touchUpInside); stack.addArrangedSubview(emit)
        let continuous = UIButton(type: .system); continuous.setTitle(demoText("Start / stop logging every second", "开始 / 停止每秒输出"), for: .normal)
        continuous.addTarget(self, action: #selector(toggleTimer), for: .touchUpInside); stack.addArrangedSubview(continuous)
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40)
        ])
    }
    @objc private func openSettings() { navigationController?.pushViewController(SparkNetLogerSettingsViewController(), animated: true) }
    @objc private func emitLogs() {
        sequence += 1
        SparkNetLoger.error("Network", demoText("Request failed", "请求失败"), context: ["statusCode": 500, "sequence": sequence])
        SparkNetLoger.warning("Cache", demoText("Cache is about to expire", "缓存即将过期"), context: ["expiresAt": Date()])
        SparkNetLoger.info("Player", demoText("Playback started 🎵", "播放开始 🎵"), context: ["song": ["id": 123, "name": "Demo"]])
        SparkNetLoger.debug("UI", demoText("First line\nSecond line <script>alert('text only')</script>", "第一行\n第二行 <script>alert('text only')</script>"))
    }
    @objc private func toggleTimer() {
        if let timer = timer { timer.invalidate(); self.timer = nil }
        else { timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.emitLogs() } }
    }
}

private func demoText(_ en: String, _ zh: String) -> String {
    (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("zh") ? zh : en
}
