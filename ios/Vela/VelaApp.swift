import SwiftUI

/// SwiftUI has no hook for the app being closed, so UIKit's is used.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_: UIApplication) {
        Intercom.shared.willTerminate()
    }
}

@main
struct VelaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var intercom = Intercom.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(intercom)
                .environmentObject(intercom.meter)
                .preferredColorScheme(.dark)
                .onAppear { intercom.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { intercom.becameActive() }
        }
    }
}
