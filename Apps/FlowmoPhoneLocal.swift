import FlowmoPhone
import SwiftUI

@main
struct FlowmoPhoneLocalApp: App {
    @StateObject private var bootstrap = PhoneStoreBootstrap(mode: .localOnly)
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let controller = bootstrap.controller {
                    PhoneRootView(controller: controller)
                        .onAppear { controller.startRunning() }
                        .onChange(of: scenePhase) { _, phase in
                            if phase == .active {
                                controller.becameActive()
                            }
                        }
                } else {
                    PhoneStoreUnavailableView(isLocalOnly: true) {
                        bootstrap.retry()
                    }
                }
            }
        }
    }
}
