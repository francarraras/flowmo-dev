import SwiftUI
import FlowmoPhone

@main
struct FlowmoPhoneApp: App {
    @StateObject private var controller = PhoneSessionController(store: PhoneSessionController.containerStore())
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            PhoneRootView(controller: controller)
                .onAppear { controller.startRunning() }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        controller.becameActive()
                    }
                }
        }
    }
}
