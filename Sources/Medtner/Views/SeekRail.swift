import SwiftUI

struct SeekRail: View {
    @Bindable var player: Player
    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !player.isPlaying || dragFraction != nil)) { timeline in
            GeometryReader { geo in
                let knob: CGFloat = dragFraction != nil ? 18 : 15
                let travel = geo.size.height - knob
                let fraction = dragFraction ?? player.fraction(at: timeline.date)
                let y = travel * CGFloat(min(max(fraction, 0), 1))

                ZStack(alignment: .top) {
                    Capsule()
                        .fill(Color(white: 0.55))
                        .frame(width: hovering ? 4 : 3)
                        .frame(maxHeight: .infinity)

                    Capsule()
                        .fill(player.accentColor.opacity(0.35))
                        .frame(width: hovering ? 4 : 3, height: y + knob / 2)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(player.accentColor)
                        .frame(width: knob, height: knob)
                        .shadow(color: player.accentColor.opacity(dragFraction != nil ? 0.8 : 0.35), radius: dragFraction != nil ? 10 : 4)
                        .overlay(alignment: .leading) {
                            if hovering || dragFraction != nil {
                                Text(formatTime(Int(Double(player.durationMs) * fraction)))
                                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(player.accentColor))
                                    .fixedSize()
                                    .offset(x: knob + 8)
                                    .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                            }
                        }
                        .offset(y: y)
                        .animation(dragFraction == nil ? nil : .interactiveSpring, value: y)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .pointerStyle(.link)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragFraction = Double((value.location.y - knob / 2) / travel)
                        }
                        .onEnded { value in
                            let target = Double((value.location.y - knob / 2) / travel)
                            player.seek(to: target)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { dragFraction = nil }
                        }
                )
                .onHover { hover in withAnimation(.spring(response: 0.25)) { hovering = hover } }
            }
        }
        .frame(width: 26)
    }
}
