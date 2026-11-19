import SwiftUI
import UIKit

/// Figma foundation colors in light appearance, adaptive colors in dark appearance.
enum StudyColors {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.38, green: 0.82, blue: 0.95, alpha: 1)
            : UIColor(red: 0, green: 116/255, blue: 156/255, alpha: 1)
    })

    static let bodyText = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .label
            : UIColor(red: 19/255, green: 42/255, blue: 54/255, alpha: 1)
    }

    static let secondaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .secondaryLabel
            : UIColor(red: 80/255, green: 98/255, blue: 111/255, alpha: 1)
    })

    static let error = Color(uiColor: .systemRed)
}

extension StudyColors {
    static let reading = adaptive(0xB6EFFF, 0x164856)
    static let listening = adaptive(0xFFD7A5, 0x583D26)
    static let writing = adaptive(0xE3D2FB, 0x473659)
    static let speaking = adaptive(0xC8EAC8, 0x2D4834)
    static let levelCard = adaptive(0x112D3B, 0x193A49)
    static let mockCard = adaptive(0xEAF8FC, 0x1D343F)
    static let ink = Color(uiColor: bodyText)

    private static func adaptive(_ light: Int, _ dark: Int) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}
