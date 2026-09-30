import SwiftUI

struct RevealRenderer: TextRenderer, Animatable {
    var progress: Double
    var stagger = 0.035
    var travel: CGFloat = 18

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        if progress >= 1 {
            for line in layout { context.draw(line) }
            return
        }
        let glyphs = layout.flatMap { $0 }.flatMap { $0 }
        let count = Double(max(glyphs.count, 1))
        let span = 1 + stagger * count
        for (index, glyph) in glyphs.enumerated() {
            let start = stagger * Double(index)
            let local = min(max((progress * span - start), 0), 1)
            let eased = 1 - pow(1 - local, 3)
            guard eased < 1 else {
                context.draw(glyph, options: .disablesSubpixelQuantization)
                continue
            }
            guard eased > 0 else { continue }
            var copy = context
            copy.opacity = eased
            copy.translateBy(x: 0, y: travel * (1 - eased))
            copy.addFilter(.blur(radius: 6 * (1 - eased)))
            copy.draw(glyph, options: .disablesSubpixelQuantization)
        }
    }
}

struct TextReveal: Transition {
    static var properties: TransitionProperties { TransitionProperties(hasMotion: true) }

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.textRenderer(RevealRenderer(progress: phase.isIdentity ? 1 : 0))
    }
}
