import AppKit
import SwiftUI
import Foundation
import Darwin
let mode = CommandLine.arguments[1]
let output = URL(fileURLWithPath: CommandLine.arguments[2])
func record(_ text: String) {
    let data = Data((text + "\n").utf8)
    if FileManager.default.fileExists(atPath: output.path), let handle = try? FileHandle(forWritingTo: output) {
        handle.seekToEndOfFile(); handle.write(data); try? handle.close()
    } else { try? data.write(to: output) }
}
@MainActor final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var delegateCalls = 0
    var ready = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        record("launched mode=\(mode)")
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 430, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Isolated sheet termination probe"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: Root())
        self.window = window
        window.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now()+5) { record("hard timeout"); Darwin.exit(2) }
    }
    func sheetReady(_ sheet: NSWindow) {
        guard !ready else { return }; ready=true
        record("sheet=\(sheet.isSheet) defaultPrevents=\(sheet.preventsApplicationTerminationWhenModal)")
        if mode.hasPrefix("allow") { sheet.preventsApplicationTerminationWhenModal = false }
        record("effectivePrevents=\(sheet.preventsApplicationTerminationWhenModal)")
        DispatchQueue.main.asyncAfter(deadline: .now()+0.2) {
            record("requestTerminate")
            if mode.hasSuffix("appleevent") {
                record("AppleQuitSent=\(NSRunningApplication.current.terminate())")
            } else { NSApp.terminate(nil) }
            record("terminateReturned delegateCalls=\(self.delegateCalls)")
            DispatchQueue.main.asyncAfter(deadline: .now()+0.2) { record("blockedObserved"); Darwin.exit(0) }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        delegateCalls += 1; record("applicationShouldTerminate"); return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { record("applicationWillTerminate") }
}
struct Root: View {
    var body: some View {
        Text("Isolated fixture").frame(width: 430, height: 300)
            .sheet(isPresented: .constant(true)) { Text("Settings-like sheet").frame(width: 300, height: 200).interactiveDismissDisabled().background(Probe()) }
    }
}
struct Probe: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView { ProbeView() }
    func updateNSView(_ nsView: ProbeView, context: Context) {}
}
final class ProbeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { (NSApp.delegate as? Delegate)?.sheetReady(window) }
    }
}
@main struct Entry {
    @MainActor static func main() {
        let delegate = Delegate()
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        _ = delegate
    }
}
