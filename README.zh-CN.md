# SparkNetLoger

[English](README.md) | **简体中文**

面向 iOS 的 Swift 日志库，内置网页查看器。在同一 Wi-Fi 下用浏览器查看 App 实时日志，无需连接数据线。基于 [Glider](https://github.com/immobiliare/Glider) 实现。

> 本项目使用 [MIT 许可证](LICENSE)，[GitHub 仓库](https://github.com/dangercheng/SparkNetLoger) 已公开，无需访问授权。尚未发布到公共 CocoaPods 仓库。

## 功能

- error、warning、info、debug 四种等级，支持 Tag 和结构化 context。
- 自动记录调用处的文件名与行号，控制台、格式化网页及纯文本视图均可显示。
- 搜索正文、Tag、文件行号和 context，组合等级与 Tag 筛选。
- 筛选区域可收起，日志容器独立滚动。距离底部超过 100px 暂停自动跟随，回到 100px 内后在下一次更新恢复。
- 纯文本视图、手动选择复制、一键复制全部筛选结果，支持局域网 HTTP 页面的复制回退。
- 中英文界面：App 跟随系统，网页可切换语言并保存选择。
- 内存保留最近 2000 条日志，支持重连同步和去重。
- HTTP 优先使用 **8848**，被占用时自动选择可用端口，并提示实际访问地址。

## 环境要求与 Demo

- iOS 15 及以上，Swift 5 语言模式，CocoaPods。
- 手机与电脑连接同一 Wi-Fi；查看日志时让 App 保持前台。

```sh
git clone --branch 0.1.2 https://github.com/dangercheng/SparkNetLoger.git
cd SparkNetLoger/Example
pod install
open SparkNetLogerDemo.xcworkspace
```

在 Xcode 中选择开发团队和设备，以 **Debug** 配置运行。进入「设置 · 实时日志」开启开关，在电脑浏览器打开显示的 HTTP 地址。Demo 支持输出四种等级日志或每秒持续输出；安装完成后可拔掉数据线。

## CocoaPods 接入

通过 HTTPS 从公开 GitHub 仓库安装 **0.1.2**，无需登录 GitHub 或配置 SSH：

```ruby
platform :ios, '15.0'
use_frameworks!

target 'YourApp' do
  pod 'SparkNetLoger', :git => 'https://github.com/dangercheng/SparkNetLoger.git',
      :tag => '0.1.2'
end
```

执行 `pod install`，并将 `Podfile.lock` 纳入版本管理。当前尚未发布到 CocoaPods trunk，请保留显式 Git 地址和标签。

本地开发时，可仅将 `SparkNetLoger` 声明替换为检出目录的路径：

```ruby
pod 'SparkNetLoger', :path => '../SparkNetLoger'
```

GliderLogger 由 SparkNetLoger 的 `~> 2` 依赖自动安装（>= 2.0 且 < 3.0），无需单独声明。本版本使用 CocoaPods 公共源中的 2.0.0 验证。

默认全局禁用日志，宿主需要在启动时显式启用：

```swift
import SparkNetLoger

// 构建条件由宿主决定，库本身没有 Debug / Release 限制。
#if DEBUG
SparkNetLoger.configure(enabled: true)
#else
SparkNetLoger.configure(enabled: false)
#endif
```

`configure(enabled: false)` 停止服务、清空内存历史并禁用控制台输出，但保留用户保存的实时日志开关选择。重新启用库时恢复该选择，无需先打开设置页。

## 输出日志

```swift
SparkNetLoger.error("Network", "请求失败", context: ["statusCode": 500])
SparkNetLoger.warning("Cache", "缓存即将过期", context: ["expiresAt": Date()])
SparkNetLoger.info("Player", "播放开始", context: ["song": ["id": 123]])
SparkNetLoger.debug("UI", "页面加载完成")
```

Tag 是第一个必传参数，空白 Tag 归入 `Default`，context 默认为空字典。四种方法自动采集 `file: String = #fileID` 和 `line: UInt = #line`，仅输出文件名与行号，不输出完整路径或函数名。封装日志入口时请继续传递调用位置：

```swift
func appLog(_ message: String, file: String = #fileID, line: UInt = #line) {
    SparkNetLoger.info("App", message, file: file, line: line)
}
```

不拦截 `print` 或 `NSLog`。正文、Tag 和用户 context 保留原始语言，界面语言切换不会翻译日志内容。

context 在调用线程转换为独立 JSON 快照。Date 使用 ISO 8601，URL 转为字符串，其他对象使用描述文本，非有限数字转为字符串。嵌套最多 8 层，正文和 context 分别最多 32 KiB，Tag 最多 1 KiB；超限内容带截断标记。传入日志时不要同时修改可变容器。

禁用时不执行 message 自动闭包、不转换 context，但 Swift 仍会在进入方法前求值 Tag 和 context 参数表达式。请勿记录密码或令牌。

## 设置界面与状态

```swift
navigationController?.pushViewController(
    SparkNetLogerSettingsViewController(), animated: true
)
```

也可以自建界面：

```swift
SparkNetLoger.startLiveLogging()
SparkNetLoger.stopLiveLogging()
let state = SparkNetLoger.state

// 将返回的 token 保存在实例属性中。
observation = SparkNetLoger.observeState { state in
    // 主线程回调。
    print(state.phase, state.webURL as Any, state.connectionCount)
    print(state.noticeMessage as Any, state.errorMessage as Any)
}
```

状态区分全局禁用、关闭、等待 Wi-Fi、启动中、运行中和失败。旧的 `paused` 状态保留以兼容现有代码，退后台不再触发。`noticeMessage` 提供端口切换等非致命提示，`errorMessage` 提供错误。实时开关初始关闭，选择保存在 `UserDefaults`；退后台和网络错误不改变选择。主动关闭实时日志、全局禁用或进程退出会清空历史。

服务控制会派发到主线程，状态查询同步返回主线程快照。不要在主线程阻塞等待另一个正在查询状态的线程。释放观察 token 或调用 `cancel()` 可停止观察。

## 语言支持

- **App 和 Demo：** 跟随系统首选语言。所有 `zh` 变体使用简体中文；英语及其他未支持语言回退到英语。更改系统语言后重新启动 App。
- **网页：** 初始跟随浏览器语言，通过 **English / 中文** 切换全部界面文案，不清空日志、搜索或筛选。选择保存在当前来源的浏览器本地存储中；IP 或端口变化后属于另一来源。存储不可用时，当前页面仍可切换语言。
- 原生翻译集中在 `Sources/Localization.swift`，网页翻译集中在 `Resources/Web/app.js`。系统生成的错误保留操作系统提供的语言。

## 网页与网络行为

使用 App 中显示的地址，通常为 `http://手机IP:8848/`。每次启动优先尝试 8848；绑定冲突时由系统分配可用端口，并更新设置页提示和地址。Glider WebSocket 尝试 `49152...49251`，网页自动读取实际端口。

服务仅监听 Wi-Fi，不使用云服务、Bonjour 或局域网扫描。网页资源随 Pod 打包，HTTP 只接受固定资源的 GET 请求，不开放任意本地文件。查看器面向可信开发网络，未提供身份认证或 TLS。

App 进入后台或锁屏时不会主动停止 HTTP 服务或断开 WebSocket 连接。iOS 仍可能挂起或终止 App，因此无法保证后台持续传输日志。回到前台会重新检查服务，必要时恢复，正常连接保持不变；IP 或端口变化时请使用新地址。浏览器断线后按 1、2、4、8、10 秒间隔重试，主动关闭实时日志后停止重试。

等级与 Tag 同组内取或、不同组之间取且，搜索不区分大小写。格式化日志可展开 context；纯文本包含时间、等级、Tag、文件行号、正文和非空 context。「复制全部」复制当前筛选结果。「清空日志」仅影响当前浏览器，不清空手机历史。暂停自动滚动不暂停接收，「滚动到底部」不会改变自动滚动开关。

协议版本 1 包括 `historyStart`、`logs`、`historyEnd`、`closed` 和 `suspended`。日志字段为 `sessionID`、`sequence`、`version`、`timestamp`、`level`、`tag`、`message`、`context`、`file` 和 `line`。旧日志缺少文件行号仍可显示。

### 已知限制

Glider 2.0.0 的 `WebSocketPeer.stop()` 实现为空。为避免上游回调访问已释放对象，接收过连接的旧服务实例会保留到进程退出，反复重启可能积累实例。停止监听不保证物理连接及相关资源立即释放。

封装未消除 Glider 内部并发风险，也不承诺慢客户端内存硬上限。日志每批最多 20 条，通常每 100ms 推送。高负载、长时间运行和生命周期行为需真机验证；模拟器回环测试不能替代手机到电脑的 Wi-Fi 验证。

## 测试

```sh
node --test Tests/web.test.js
ruby Scripts/validate_pod.rb
cd Example
xcodebuild -workspace SparkNetLogerDemo.xcworkspace -scheme SparkNetLogerDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

请按本机环境选择可用模拟器。`Scripts/generate_project.rb` 仅用于首次生成工程，已有工程时拒绝覆盖。[VALIDATION.md](VALIDATION.md) 保存历史验证记录，最新结果以当前测试输出为准。

## 发布状态与许可证

Copyright (c) 2026 chengdengjian。SparkNetLoger 使用 [MIT 许可证](LICENSE)，尚未发布到 CocoaPods trunk。第三方依赖保留各自许可，Glider 使用 MIT。
