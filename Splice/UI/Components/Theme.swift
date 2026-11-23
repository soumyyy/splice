import SwiftUI

/// Splice's palette: true black with hairline borders. The only colour on screen comes from the zones.
extension Color {
  static let hairline = Color(hex: 0x2A2A2E)
  static let textPrimary = Color(hex: 0xF5F5F7)
  static let textSecondary = Color(hex: 0x8E8E93)
}

extension Font {
  /// Condensed numerals for the live heart rate, like a race clock.
  static func bpm(_ size: CGFloat) -> Font {
    .system(size: size, weight: .semibold, design: .default).width(.compressed)
  }
}
