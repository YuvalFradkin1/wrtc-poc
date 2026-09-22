import Foundation
import WebKit
import AppKit

// WKWebView requires RunLoop to process callbacks — must run on main thread
// Use a completion block pattern with NSRunLoop

var statusMessages: [String] = []
var isDone = false

// Snapshot DiagnosticReports before run
func diagLogs() -> Set<String> {
    let d = "\(NSHomeDirectory())/Library/Logs/DiagnosticReports"
    return Set((try? FileManager.default.contentsOfDirectory(atPath: d)) ?? [])
}

class MsgHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ c: WKUserContentController,
                               didReceive m: WKScriptMessage) {
        let s = m.body as? String ?? ""
        print("[JS] \(s)")
        statusMessages.append(s)
        if s.hasPrefix("DONE") || s.hasPrefix("FAIL") {
            isDone = true
        }
    }
}

let pre = diagLogs()
print("[PoC] Pre-existing crash logs: \(pre.count)")

let htmlPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Sources/trigger.html"
guard let html = try? String(contentsOfFile: htmlPath, encoding: .utf8) else {
    print("[ERROR] Cannot read \(htmlPath)"); exit(1)
}
print("[PoC] HTML loaded (\(html.count) bytes)")

// Must setup on main thread
let cfg = WKWebViewConfiguration()
let uc = WKUserContentController()
let handler = MsgHandler()
uc.add(handler, name: "status")
cfg.userContentController = uc

// Allow local file access and WebCodecs
cfg.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let win = NSWindow(contentRect: NSMakeRect(0, 0, 200, 200),
                   styleMask: [.titled, .resizable],
                   backing: .buffered, defer: false)
win.title = "PoC"

let wv = WKWebView(frame: NSMakeRect(0, 0, 200, 200), configuration: cfg)
win.contentView = wv
win.makeKeyAndOrderFront(nil)

wv.loadHTMLString(html, baseURL: URL(string: "https://poc.test"))
print("[PoC] WKWebView loaded, running RunLoop for 25s...")

// Run the main RunLoop — required for WKWebView to process JS
let deadline = Date().addingTimeInterval(25)
while Date() < deadline && !isDone {
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}

print("[PoC] Done. isDone=\(isDone) msgs=\(statusMessages)")
print("[PoC] Waiting 3s for crash reports...")
Thread.sleep(forTimeInterval: 3)

let post = diagLogs()
let newLogs = post.subtracting(pre)
let diagDir = "\(NSHomeDirectory())/Library/Logs/DiagnosticReports"
print("[PoC] New crash logs: \(newLogs.count)")

for f in newLogs {
    print("[CRASH LOG] \(f)")
    let p = "\(diagDir)/\(f)"
    if let content = try? String(contentsOfFile: p, encoding: .utf8) {
        let lines = content.components(separatedBy: "\n").prefix(80)
        print(lines.joined(separator: "\n"))
        print("---")
    }
}

if !newLogs.isEmpty {
    print("[!] dfe0d84a7b CONFIRMED: GPU/media process crash detected")
    exit(0)
} else if statusMessages.contains(where: { $0.hasPrefix("DECODED") || $0.hasPrefix("COPYTO") }) {
    print("[~] Decoder reached but no crash — may need larger malformed frame")
    exit(2)
} else {
    print("[?] No JS messages — WKWebView or WebCodecs issue")
    exit(3)
}
