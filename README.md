<p align="center">
  <img src="docs/images/logo.png" alt="SparkNetLoger logo" width="240">
</p>

# SparkNetLoger

**English** | [简体中文](README.zh-CN.md)

A Swift logging library for iOS with a built-in web viewer. View live app logs from a browser on the same Wi-Fi, without a USB connection. Powered by [Glider](https://github.com/immobiliare/Glider).

> Licensed under [MIT](LICENSE). The [GitHub repository](https://github.com/dangercheng/SparkNetLoger) is private and requires access. The project has not been published to the public CocoaPods registry.

## Features

- Four log levels: error, warning, info and debug, with tags and structured context.
- Automatic call-site file name and line number in console, formatted web logs and plain-text logs.
- Search messages, tags, source locations and context; combine level and tag filters.
- Collapsible filters, a fixed-height log area, and smart auto-scroll: scroll more than 100px from the bottom to pause following, then return within 100px to resume on the next update.
- Plain-text view, text selection, and copying all filtered logs, including a fallback for local HTTP pages.
- English and Simplified Chinese interface text. The app follows the system language; the web viewer supports a saved language choice.
- Up to 2000 recent entries in memory, with reconnect synchronization and deduplication.
- Preferred HTTP port **8848**. If occupied, the service selects an available port and displays a notice with the actual address.

## Requirements and demo

- iOS 15 or later; Swift 5 language mode; CocoaPods.
- Phone and computer on the same Wi-Fi. Keep the app in the foreground while viewing logs.

```sh
git clone git@github.com:dangercheng/SparkNetLoger.git
cd SparkNetLoger/Example
pod install
open SparkNetLogerDemo.xcworkspace
```

Select your development team and device in Xcode, then run the **Debug** configuration. In the demo, open **Settings · Live Logs**, enable logging, and open the displayed HTTP address in a browser. The demo can emit all four levels or generate logs once per second. After installing the app, the USB cable may be disconnected.

## Integrating with CocoaPods

Use a local checkout as shown below. This example assumes the library is next to your app directory; adjust the relative path as needed:

```ruby
platform :ios, '15.0'
use_frameworks!

target 'YourApp' do
  pod 'GliderLogger', :git => 'https://github.com/immobiliare/Glider.git',
      :commit => 'c93275370925fbdb30cbe5507c6cdd2d0afe426f'
  pod 'SparkNetLoger', :path => '../SparkNetLoger'
end
```

To install directly from the private repository, replace the `SparkNetLoger` line with the following and make sure your GitHub account has access and SSH authentication is configured:

```ruby
pod 'SparkNetLoger', :git => 'git@github.com:dangercheng/SparkNetLoger.git', :branch => 'main'
```

No version tag has been published yet; keep `Podfile.lock` to retain the resolved revision.

The demo pins the upstream Glider commit whose manifest declares version 2.0.5. Use the same pin: this project was validated with that revision, and its upstream dependency source has not been modified. The upstream 2.0.5 Git tag used during initial setup declared a different podspec version.

Logging is globally disabled by default. Enable it explicitly at app startup:

```swift
import SparkNetLoger

// Build configuration is the host app's choice, not a restriction in the library.
#if DEBUG
SparkNetLoger.configure(enabled: true)
#else
SparkNetLoger.configure(enabled: false)
#endif
```

`configure(enabled: false)` stops the service, clears in-memory history and disables console output. It preserves the saved live-logging preference; enabling the library restores that preference without requiring the settings screen to be opened.

## Writing logs

```swift
SparkNetLoger.error("Network", "Request failed", context: ["statusCode": 500])
SparkNetLoger.warning("Cache", "Cache expiring", context: ["expiresAt": Date()])
SparkNetLoger.info("Player", "Playback started", context: ["song": ["id": 123]])
SparkNetLoger.debug("UI", "Screen loaded")
```

The first argument is a required tag. Blank tags become `Default`; context defaults to an empty dictionary. All four methods capture `file: String = #fileID` and `line: UInt = #line`. Only the file name and line number are displayed; full paths and function names are not emitted. Forward these parameters when wrapping the API:

```swift
func appLog(_ message: String, file: String = #fileID, line: UInt = #line) {
    SparkNetLoger.info("App", message, file: file, line: line)
}
```

The library does not intercept `print` or `NSLog`. Log messages, tags and user context are preserved in their original language; interface language changes do not translate them.

Context is converted to an independent JSON snapshot on the calling thread. Dates use ISO 8601, URLs become strings, and other objects use their descriptions. Non-finite numbers become strings. Nesting is limited to 8 levels, messages and context to 32 KiB each, and tags to 1 KiB; oversized content is marked as truncated. Do not modify mutable containers while passing them into a log call.

When disabled, the message autoclosure is not evaluated and context is not converted. Swift still evaluates the tag and context argument expressions before entering the method. Avoid logging passwords or tokens.

## Settings and state

```swift
navigationController?.pushViewController(
    SparkNetLogerSettingsViewController(), animated: true
)
```

For custom interfaces:

```swift
SparkNetLoger.startLiveLogging()
SparkNetLoger.stopLiveLogging()
let state = SparkNetLoger.state

// Keep the returned token in an instance property.
observation = SparkNetLoger.observeState { state in
    // Called on the main thread.
    print(state.phase, state.webURL as Any, state.connectionCount)
    print(state.noticeMessage as Any, state.errorMessage as Any)
}
```

Phases distinguish disabled, off, waiting for Wi-Fi, starting, running, background-paused and failed. `noticeMessage` reports nonfatal events such as port changes; `errorMessage` reports failures. The switch preference is saved in `UserDefaults`, initially off. Background suspension and connection failures do not change it. History is cleared when live logging is explicitly stopped, the library is disabled, or the process exits.

Service control is dispatched to the main thread. State queries synchronously return a main-thread snapshot, so do not block the main thread while waiting for another thread to query state. Releasing the observation token or calling `cancel()` ends observation.

## Language support

- **App and demo:** follow the first system preferred language. `zh` variants use Simplified Chinese; English and unsupported languages use English. Restart the app after changing its system language.
- **Web viewer:** initially follows the browser language. The **English / 中文** selector changes all UI text without clearing logs, search or filter selections. The choice is saved in browser local storage for that origin; a new IP or port has separate storage. If storage is unavailable, switching still works for the current page.
- Native translations are centralized in `Sources/Localization.swift`; web translations are in `Resources/Web/app.js`. System-generated errors retain the language supplied by the operating system.

## Web viewer and network behavior

Use the address shown in the app, usually `http://PHONE_IP:8848/`. Each startup tries 8848 first. On a bind conflict, a system-assigned port is used and the settings screen shows the new address. Glider WebSocket uses `49152...49251`; the webpage obtains its actual port automatically.

The service listens on Wi-Fi only. It uses no cloud service, Bonjour discovery or LAN scanning. All web resources are packaged with the Pod. HTTP accepts only GET requests for fixed resources, not arbitrary local files. The viewer is intended for trusted development networks; it does not provide authentication or TLS.

Entering the background or locking the phone pauses the service. Returning to the foreground restarts it; use the displayed address if the IP or port changed. Browsers reconnect after 1, 2, 4, 8 and then 10 seconds; explicitly stopping live logging ends retries.

Level/tag selections are OR within each group and AND across groups. Search is case-insensitive. Formatted entries expand to show context. Plain-text entries include time, level, tag, source location, message and nonempty context. **Copy all** copies the current filtered results. **Clear logs** affects only the current browser, not the phone's history. Pausing auto-scroll does not pause reception; **Scroll to bottom** does not change the auto-scroll switch.

Protocol version 1 uses `historyStart`, `logs`, `historyEnd`, `closed` and `suspended`. Entries contain `sessionID`, `sequence`, `version`, `timestamp`, `level`, `tag`, `message`, `context`, `file` and `line`. Older entries without source locations remain displayable.

### Known limitations

Glider 2.0.5 has an empty `WebSocketPeer.stop()` implementation. Previously used servers are retained until process exit to avoid upstream callbacks accessing released objects, so repeated restarts can accumulate instances. Stopping listeners does not guarantee immediate physical disconnection or release of all connection resources.

The wrapper does not eliminate Glider's internal concurrency risks or enforce a hard slow-client memory bound. Logs are sent in batches of up to 20, normally every 100ms. Test heavy workloads, long sessions and lifecycle behavior on real devices. Simulator loopback tests do not replace phone-to-computer Wi-Fi verification.

## Testing

```sh
node --test Tests/web.test.js
ruby Scripts/validate_pod.rb
cd Example
xcodebuild -workspace SparkNetLogerDemo.xcworkspace -scheme SparkNetLogerDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Choose an available simulator on your machine. `Scripts/generate_project.rb` is only for creating the initial project and refuses to overwrite an existing one. [VALIDATION.md](VALIDATION.md) contains historical validation notes in Chinese; consult current test output for the latest results.

## Release status and license

Copyright (c) 2026 chengdengjian. SparkNetLoger is licensed under the [MIT License](LICENSE). It is not published to CocoaPods trunk. Third-party dependencies retain their own licenses; Glider uses MIT.
