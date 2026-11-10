import Combine
import Foundation

enum VehicleUpgrade: String, CaseIterable, Identifiable {
    case armor, engine, magazine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .armor: return "Reinforced body"
        case .engine: return "Engine tune"
        case .magazine: return "Extended magazine"
        }
    }

    var symbol: String {
        switch self {
        case .armor: return "shield.lefthalf.filled"
        case .engine: return "engine.combustion.fill"
        case .magazine: return "rectangle.stack.fill"
        }
    }

    var detail: String {
        switch self {
        case .armor: return "15% less impact damage per level"
        case .engine: return "+4 km/h per level"
        case .magazine: return "+4 rounds per magazine per level"
        }
    }

    var basePrice: Int {
        switch self {
        case .armor: return 30
        case .engine: return 45
        case .magazine: return 35
        }
    }
}

/// Local garage purchases survive relaunches; passing nil storage creates an isolated run profile.
@MainActor
final class GarageProgress: ObservableObject {
    static let maximumLevel = 3
    private static let storageKey = "TheDrive.garage.v1"

    @Published private(set) var wallet: Int
    @Published private var levels: [String: Int]
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        let saved = defaults?.dictionary(forKey: Self.storageKey) ?? [:]
        wallet = max(0, (saved["wallet"] as? Int) ?? 0)
        levels = Dictionary(uniqueKeysWithValues: VehicleUpgrade.allCases.map { upgrade in
            (upgrade.rawValue, min(Self.maximumLevel, max(0, (saved[upgrade.rawValue] as? Int) ?? 0)))
        })
    }

    func level(for upgrade: VehicleUpgrade) -> Int { levels[upgrade.rawValue] ?? 0 }

    /// A maxed upgrade has no next price and cannot consume cash.
    func cost(for upgrade: VehicleUpgrade) -> Int? {
        let current = level(for: upgrade)
        guard current < Self.maximumLevel else { return nil }
        return upgrade.basePrice * (current + 1)
    }

    @discardableResult
    func purchase(_ upgrade: VehicleUpgrade) -> Bool {
        guard let price = cost(for: upgrade), wallet >= price else { return false }
        // Purchases run synchronously on the main actor, so rapid taps cannot spend a balance twice.
        wallet -= price
        levels[upgrade.rawValue] = level(for: upgrade) + 1
        persist()
        return true
    }

    /// Call with newly earned cash, rather than the run's cumulative total.
    func award(distanceCash: Int) {
        guard distanceCash > 0 else { return }
        let result = wallet.addingReportingOverflow(distanceCash)
        wallet = result.overflow ? Int.max : result.partialValue
        persist()
    }

    private func persist() {
        var saved = levels
        saved["wallet"] = wallet
        defaults?.set(saved, forKey: Self.storageKey)
    }
}
