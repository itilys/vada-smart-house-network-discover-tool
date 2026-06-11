import SwiftUI

struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: () -> Content

    init(spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
#if os(macOS)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
#else
        content()
#endif
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 16, interactive: Bool = false) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, interactive: interactive))
    }
}

private struct GlassPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

#if os(macOS)
        if #available(macOS 26.0, *), colorScheme == .dark {
            if interactive {
                content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.stroke(Color.primary.opacity(colorScheme == .light ? 0.08 : 0.12), lineWidth: 1)
                }
        }
#else
        content
            .background(.regularMaterial, in: shape)
            .overlay {
                shape.stroke(Color.primary.opacity(colorScheme == .light ? 0.08 : 0.12), lineWidth: 1)
            }
#endif
    }
}

struct PrimaryGlassButton<LabelContent: View>: View {
    let action: () -> Void
    @ViewBuilder var label: () -> LabelContent

    var body: some View {
#if os(macOS)
        if #available(macOS 26.0, *) {
            Button(action: action, label: label)
                .buttonStyle(.glassProminent)
        } else {
            Button(action: action, label: label)
                .buttonStyle(.borderedProminent)
        }
#else
        Button(action: action, label: label)
            .buttonStyle(.borderedProminent)
#endif
    }
}
