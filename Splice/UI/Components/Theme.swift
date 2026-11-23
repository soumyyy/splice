import SwiftUI

extension Color {
  static let spliceCard = Color(white: 0.11)
}

extension Double {
  var kilometers: String {
    String(format: "%.2f km", self / 1000)
  }
}

struct Card<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    content
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.spliceCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }
}
