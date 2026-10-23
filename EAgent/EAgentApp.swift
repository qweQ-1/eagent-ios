import SwiftUI

@main
struct EAgentApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var engine = AgentEngine(settings: AppSettings.load())
    @StateObject private var shareBroker = ShareBroker()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(engine)
                .environmentObject(shareBroker)
        }
    }
}
