import FlowmoPhone
import SwiftUI

@main
struct FlowmoPhoneApp: App {
    @StateObject private var bootstrap = PhoneStoreBootstrap()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let controller = bootstrap.controller {
                    PhoneRootView(controller: controller)
                        .onAppear { controller.startRunning() }
                        .onChange(of: scenePhase) { phase in
                            if phase == .active {
                                controller.becameActive()
                            }
                        }
                } else {
                    PhoneStoreUnavailableView {
                        bootstrap.retry()
                    }
                }
            }
        }
    }
}
