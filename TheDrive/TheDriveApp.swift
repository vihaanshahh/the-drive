import SwiftUI

@main
struct TheDriveApp: App {
    var body: some Scene {
        WindowGroup { GameView().preferredColorScheme(.dark).statusBarHidden() }
    }
}
