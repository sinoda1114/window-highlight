import CoreGraphics

struct DisplayCoordinateSpace {
    let appKitFrame: CGRect
    let coreGraphicsBounds: CGRect
}

enum CoordinateConverter {
    static func convertAccessibilityFrameToAppKit(
        _ frame: CGRect,
        displays: [DisplayCoordinateSpace],
        fallbackMainScreenFrame: CGRect?
    ) -> CGRect? {
        let center = CGPoint(x: frame.midX, y: frame.midY)

        for display in displays where display.coreGraphicsBounds.contains(center) {
            return CGRect(
                x: display.appKitFrame.minX + (frame.minX - display.coreGraphicsBounds.minX),
                y: display.appKitFrame.minY + (display.coreGraphicsBounds.maxY - frame.maxY),
                width: frame.width,
                height: frame.height
            )
        }

        guard let fallbackMainScreenFrame else {
            return nil
        }

        return CGRect(
            x: frame.minX,
            y: fallbackMainScreenFrame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}
