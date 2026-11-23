import SwiftUI

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xff) / 255,
      green: Double((hex >> 8) & 0xff) / 255,
      blue: Double(hex & 0xff) / 255
    )
  }

  static let spliceAccent = Color(hex: 0xFF4D3D)

  static func zone(_ index: Int) -> Color {
    Color(hex: ZonePalette.hex[max(0, min(4, index))])
  }
}
