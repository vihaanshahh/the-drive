import SwiftUI

@main
struct TheDriveApp: App {
    var body: some Scene {
        WindowGroup { LaunchView().preferredColorScheme(.dark).statusBarHidden() }
    }
}
