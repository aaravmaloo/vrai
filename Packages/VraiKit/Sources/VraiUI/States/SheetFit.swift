import SwiftUI

extension WindowModel {
    func sheetWidth(_ wanted: CGFloat) -> CGFloat {
        let total = sync.windowWidth
        guard total > 0 else { return wanted }
        return min(wanted, max(total - Vrai.Space.s16 * 2, Vrai.Size.field + Vrai.Space.s64))
    }
}
