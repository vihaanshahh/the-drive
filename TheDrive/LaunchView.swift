import Combine
import SwiftUI

/// The launch artwork appears before the SceneKit world and its character meshes are created.
struct LaunchView: View {
    @StateObject private var startup = GameStartup()

    var body: some View {
        Group {
            if let game = startup.game {
                GameView(game: game, garage: startup.garage)
            } else {
                LoadingScreen()
            }
        }
        .task { await startup.prepare() }
    }
}

@MainActor
private final class GameStartup: ObservableObject {
    @Published private(set) var game: GameModel?
    let garage = GarageProgress()
    private var preparing = false

    func prepare() async {
        guard game == nil, !preparing else { return }
        preparing = true
        // Allow SwiftUI to present the loading view before doing main-actor SceneKit work.
        await Task.yield()
        guard !Task.isCancelled else { preparing = false; return }
        game = GameModel(garage: garage)
        preparing = false
    }
}

struct LoadingScreen: View {
    private let sand = Color(red: 0.96, green: 0.78, blue: 0.48)

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Color(red: 0.075, green: 0.065, blue: 0.06)
                Image("LaunchArtwork")
                    .resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                LinearGradient(colors: [.black.opacity(0.52), .clear], startPoint: .leading, endPoint: .trailing)
                VStack(alignment: .leading, spacing: 12) {
                    Text("GUJARAT / DESERT ESCAPE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(sand)
                    Text("THE\nDRIVE")
                        .font(.system(size: min(66, proxy.size.height * 0.17), weight: .black, design: .rounded))
                        .tracking(6).lineSpacing(-6).foregroundStyle(.white)
                    HStack(spacing: 10) {
                        ProgressView().tint(sand)
                        Text("PREPARING THE ROAD")
                            .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(sand)
                    }.padding(.top, 15)
                }
                .padding(.leading, max(44, proxy.size.width * 0.09))
            }
        }.ignoresSafeArea()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading The Drive")
    }
}
