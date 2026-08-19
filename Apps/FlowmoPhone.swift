import SwiftUI
import FlowmoPhone

@main
struct FlowmoPhoneApp: App {
    @StateObject private var controller = PhoneSessionController(store: PhoneSessionController.containerStore())

    var body: some Scene {
        WindowGroup {
            PhoneRootView(controller: controller)
                .onAppear { controller.startRunning() }
        }
    }
}
