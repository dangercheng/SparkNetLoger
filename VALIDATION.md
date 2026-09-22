# 验证记录

验证日期：2026-09-21。环境：Xcode 26.2、iOS 26.2 Simulator、Swift 5 language mode、CocoaPods 1.16.2。库和 Demo deployment target 为 iOS 15.0。

## 已通过

- `pod install`：GliderLogger 2.0.5 + SparkNetLoger 0.1.0，生成 workspace 和锁文件。
- `ruby Scripts/validate_pod.rb`：私有 Pod 独立构建校验通过，使用 `--allow-warnings --skip-tests`；测试另行运行。
- Debug：11 项 XCTest 全部通过。
- Release：同样 11 项 XCTest 全部通过（测试命令启用 ENABLE_TESTABILITY；库行为没有条件编译）。
- JavaScript：3 项 Node 测试通过，覆盖历史窗口、序号去重、会话切换、context 搜索、组合过滤、稳定配色与时间格式。
- 浏览器实际交互：使用本地测试 WebSocket 夹具发送四级样例，验证显示完整时间、等级和 Tag 颜色、context 搜索与展开、等级/Tag 组合过滤、暂停滚动、清空页面、HTML 字符串作为纯文本展示。

## XCTest 覆盖

1. context 快照、基础与嵌套类型、Date/URL、非有限数值。
2. context 递归深度限制。
3. Unicode 正文和 context 大小限制。
4. 输出字段不包含文件、函数、行号；空白 Tag 归入 Default。
5. 历史环形缓存淘汰及清空。
6. 全局禁用时消息闭包不执行。
7. 全局启用时四级消息均求值，在 Debug/Release 下行为一致。
8. 持久化实时开关不被全局禁用覆盖。
9. 实际 HTTP 请求：页面、JS、CSS、配置、带 query 的页面、404；重复停止。
10. 实际 Glider 原生 WebSocket：启动、JSON 文本广播、监听停止。
11. 完整 LiveService：HTTP 配置获取、连接前历史、连接后实时日志、关闭通知、重新创建服务恢复保存的开关。

网络集成测试通过内部依赖注入使用 loopback；公开 API 的生产实现始终限制 Wi-Fi，不公开测试参数。

## 已发现并处理

- 官方 Git 标签 2.0.5 的 podspec 仍声明 2.0.3，公共索引无法安装目标版本。Demo 和接入文档固定官方 `c93275370925fbdb30cbe5507c6cdd2d0afe426f` 提交，其 manifest 声明 2.0.5。
- Glider 旧服务释放后可能由连接回调触发 unowned 引用崩溃。封装保留曾接收连接的旧服务到进程结束；停止监听与转发。修复后 Debug/Release 网络测试均无该崩溃。
- 浏览器实测发现时间只显示毫秒，已修正为完整时分秒与毫秒并添加回归测试。

## 已知警告和限制

- 初次验证使用的 example.invalid 仓库占位地址现已替换为 https://github.com/dangercheng/SparkNetLoger；仓库为私有，许可证为 MIT。
- Glider 在当前工具链下产生旧 deployment target、Sendable 和扩展协议一致性等警告；未修改依赖源码。
- 原生 WebSocket 的 stop() 不完整，旧服务实例会积累；不承诺连接物理即时释放、慢连接内存硬上限或消除 Glider 内部线程竞态。
- 浏览器样例测试验证前端；loopback 测试验证网络链路。它们均不替代实体手机、Wi-Fi 和系统生命周期验收。

## 尚需真机或专项验收

- 使用用户开发团队签名，Xcode 安装后拔掉数据线，同 Wi-Fi 电脑浏览器访问手机。
- iOS 15 实际运行（当前可用模拟器为 iOS 26.2）。
- 前后台切换、锁屏恢复、Wi-Fi 切换或 AP 客户端隔离场景。
- 真实 App 杀进程重启后的开关恢复；测试目前模拟重新创建服务读取同一 UserDefaults。
- 多浏览器长时间运行、慢连接、大量并发日志与反复开关的资源压力。
- WebSocket 候选端口全部被占用、HTTP 启动失败的设备级故障注入。
- 正常局域网下约 1 秒的端到端显示延迟。
