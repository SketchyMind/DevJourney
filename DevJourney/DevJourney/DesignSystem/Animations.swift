import SwiftUI

extension Animation {
    static let springDefault = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let springSnappy = Animation.spring(response: 0.25, dampingFraction: 0.7)
    static let springGentle = Animation.spring(response: 0.5, dampingFraction: 0.85)
    static let hoverFast = Animation.easeOut(duration: 0.15)
    static let contentTransition = Animation.easeInOut(duration: 0.25)
    static let subtleTransition = Animation.easeInOut(duration: 0.2)
}
