import SwiftUI
import FlowmoPhone

@main
struct FlowmoPhoneApp: App {
    @StateObject private var controller: PhoneSessionController
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let controller: PhoneSessionController
        do {
            let store = try PhoneSessionController.containerStore()
            controller = PhoneSessionController(store: store)
        } catch {
            fatalError(error.localizedDescription)
        }
        _controller = StateObject(wrappedValue: controller)
    }

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
