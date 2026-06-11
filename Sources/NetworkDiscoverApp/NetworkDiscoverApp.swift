import SwiftUI

#if os(macOS)
import AppKit
#endif

@main
struct NetworkDiscoverApp: App {
#if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
#endif

    var body: some Scene {
        WindowGroup("VaDa Network Discover") {
            ContentView()
#if os(macOS)
                .frame(minWidth: 1080, minHeight: 680)
#endif
        }
#if os(macOS)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Acerca de VaDa Network Discover") {
                    VaDaAboutPanel.show()
                }
            }
        }
#endif
    }
}

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let icon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private enum VaDaAboutPanel {
    static func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let credits = NSAttributedString(
            string: """
            Una utilidad gratuita para descubrir equipos en redes locales autorizadas.

            VaDa SmartHouse
            https://vadasmarthouse.com/
            """,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .paragraphStyle: paragraph
            ]
        )
        let icon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "VaDa Network Discover",
            .applicationVersion: "0.1.0",
            .applicationIcon: icon as Any,
            .credits: credits
        ])
    }
}
#endif
