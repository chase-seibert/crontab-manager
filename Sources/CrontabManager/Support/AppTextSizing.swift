import SwiftUI

enum AppTextSizing {
    static let storageKey = "appTextFontSize"
    static let defaultSize = 13.0
    static let minimumSize = 11.0
    static let maximumSize = 20.0
    static let step = 1.0

    static func increased(from size: Double) -> Double {
        clamped(size + step)
    }

    static func decreased(from size: Double) -> Double {
        clamped(size - step)
    }

    static func clamped(_ size: Double) -> Double {
        min(max(size, minimumSize), maximumSize)
    }

    static func title3(_ setting: Double, weight: Font.Weight = .regular) -> Font {
        font(baseSize: 20, setting: setting, weight: weight)
    }

    static func subheadline(_ setting: Double, weight: Font.Weight = .regular) -> Font {
        font(baseSize: 12, setting: setting, weight: weight)
    }

    static func body(_ setting: Double, weight: Font.Weight = .regular) -> Font {
        font(baseSize: 13, setting: setting, weight: weight)
    }

    static func caption(_ setting: Double, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        font(baseSize: 11, setting: setting, weight: weight, design: design)
    }

    static func caption2(_ setting: Double, weight: Font.Weight = .regular) -> Font {
        font(baseSize: 10, setting: setting, weight: weight)
    }

    static func code(_ setting: Double) -> Font {
        font(baseSize: 13, setting: setting, design: .monospaced)
    }

    private static func font(
        baseSize: Double,
        setting: Double,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: scaledSize(baseSize: baseSize, setting: setting), weight: weight, design: design)
    }

    private static func scaledSize(baseSize: Double, setting: Double) -> CGFloat {
        let delta = clamped(setting) - defaultSize
        return CGFloat(max(baseSize + delta, 9))
    }
}
