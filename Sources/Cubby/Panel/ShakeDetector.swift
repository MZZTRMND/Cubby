import Foundation

/// When the folder comes forward for a drag from another app.
enum DragSummon: String, CaseIterable, Identifiable {
    case always, shake, never

    static let key = "dragSummon"

    var id: Self { self }
    var title: String {
        switch self {
        case .always: "Always"
        case .shake: "When Shaken"
        case .never: "Never"
        }
    }
}

/// Spots a quick side-to-side shake of the pointer: three changes of direction, each
/// after a swing of at least `minSwing` points, within `window` seconds. Slow wandering
/// and small wobbles don't count.
struct ShakeDetector {
    var minSwing: CGFloat = 30
    var window: TimeInterval = 0.8
    var reversalsNeeded = 3

    /// The far end of the current swing.
    private var extreme: CGFloat?
    /// +1 moving right, -1 moving left, 0 not yet moving.
    private var direction: CGFloat = 0
    private var reversals: [TimeInterval] = []

    /// Feeds the pointer's horizontal position; true once it's been shaken.
    mutating func add(x: CGFloat, at time: TimeInterval) -> Bool {
        guard let extreme else {
            self.extreme = x
            return false
        }
        let delta = x - extreme
        if direction == 0 {
            if abs(delta) >= minSwing { direction = delta > 0 ? 1 : -1; self.extreme = x }
            return false
        }
        // Still going the same way: the swing gets longer.
        if delta * direction > 0 {
            self.extreme = x
            return false
        }
        guard abs(delta) >= minSwing else { return false }
        direction = -direction
        self.extreme = x
        reversals.append(time)
        reversals.removeAll { time - $0 > window }
        return reversals.count >= reversalsNeeded
    }
}
