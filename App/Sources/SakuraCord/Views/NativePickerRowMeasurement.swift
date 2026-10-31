import AppKit
import SwiftUI

/// Only non-grid rows need measurement. Cache their exact SwiftUI fitting size
/// when catalog text, available width or interface size changes, never during
/// scrolling.
@MainActor
final class NativePickerRowMeasurement {
    private var width: CGFloat = -1
    private var scale = InterfaceScale.factor
    private var heights: [String: CGFloat] = [:]

    func height<Content: View>(key: String, width: CGFloat, @ViewBuilder content: () -> Content) -> CGFloat {
        if abs(self.width - width) > 0.5 || scale != InterfaceScale.factor {
            self.width = width
            scale = InterfaceScale.factor
            heights.removeAll(keepingCapacity: true)
        }
        if let height = heights[key] { return height }
        let host = NSHostingView(rootView: content().frame(width: max(1, width)).fixedSize(horizontal: false, vertical: true))
        let height = host.fittingSize.height
        if heights.count >= 512 { heights.removeAll(keepingCapacity: true) }
        heights[key] = height
        return height
    }
}
