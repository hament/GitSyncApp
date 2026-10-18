import SwiftUI

@main
struct MyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            MainView(model: model)
        }
        .defaultSize(width: 1100, height: 720)
    }
}
