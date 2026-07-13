import CoreGraphics
import Foundation

private func assertEqual(_ actual: CGRect?, _ expected: CGRect, file: StaticString = #file, line: UInt = #line) {
    guard actual == expected else {
        fputs("Expected \(expected), got \(String(describing: actual))\n", stderr)
        exit(1)
    }
}

private func assertNil(_ actual: CGRect?, file: StaticString = #file, line: UInt = #line) {
    guard actual == nil else {
        fputs("Expected nil, got \(String(describing: actual))\n", stderr)
        exit(1)
    }
}

@main
private enum CoordinateConverterTestRunner {
    static func main() {
        assertEqual(
            CoordinateConverter.convertAccessibilityFrameToAppKit(
                CGRect(x: 100, y: 80, width: 500, height: 300),
                displays: [
                    DisplayCoordinateSpace(
                        appKitFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                        coreGraphicsBounds: CGRect(x: 0, y: 0, width: 1440, height: 900)
                    )
                ],
                fallbackMainScreenFrame: nil
            ),
            CGRect(x: 100, y: 520, width: 500, height: 300)
        )

        assertEqual(
            CoordinateConverter.convertAccessibilityFrameToAppKit(
                CGRect(x: 1520, y: 120, width: 600, height: 400),
                displays: [
                    DisplayCoordinateSpace(
                        appKitFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                        coreGraphicsBounds: CGRect(x: 0, y: 0, width: 1440, height: 900)
                    ),
                    DisplayCoordinateSpace(
                        appKitFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                        coreGraphicsBounds: CGRect(x: 1440, y: 0, width: 1920, height: 1080)
                    )
                ],
                fallbackMainScreenFrame: nil
            ),
            CGRect(x: 1520, y: 560, width: 600, height: 400)
        )

        assertEqual(
            CoordinateConverter.convertAccessibilityFrameToAppKit(
                CGRect(x: 20, y: 30, width: 100, height: 200),
                displays: [],
                fallbackMainScreenFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
            ),
            CGRect(x: 20, y: 370, width: 100, height: 200)
        )

        assertNil(
            CoordinateConverter.convertAccessibilityFrameToAppKit(
                CGRect(x: 20, y: 30, width: 100, height: 200),
                displays: [],
                fallbackMainScreenFrame: nil
            )
        )

        print("CoordinateConverter tests passed")
    }
}
