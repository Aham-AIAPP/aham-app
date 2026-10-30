import SwiftUI

struct PillButtonStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        AHInlineSurface(label: configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, AHSpacing.s).padding(.vertical, AHSpacing.xxs)
            .foregroundStyle(selected ? Color.ahInk : Color.ahInk60)
            .background(selected ? Color.ahSelected : Color.ahPaperAlt, in: .capsule),
            pressed: configuration.isPressed, selected: selected, radius: AHRadius.pill)
    }
}
