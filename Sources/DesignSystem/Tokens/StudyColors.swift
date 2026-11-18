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
