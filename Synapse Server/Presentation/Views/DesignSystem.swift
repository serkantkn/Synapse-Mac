//
//  DesignSystem.swift
//  Synapse Server
//
//  Liquid Glass building blocks shared by every window. macOS 26+ uses the system glass;
//  macOS 14–15 fall back to visual-effect materials. Mirrors the iOS app's DesignSystem.swift.
//

import SwiftUI
import AppKit

// MARK: - Palette

extension Color {
    static let synapseCyan = Color(red: 0.20, green: 0.80, blue: 0.98)
    static let synapseBlue = Color(red: 0.04, green: 0.52, blue: 1.00)
    static let synapseIndigo = Color(red: 0.37, green: 0.36, blue: 0.90)

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension ShapeStyle where Self == LinearGradient {
    /// Brand gradient: logo, hero symbols and avatars.
    static var synapseGradient: LinearGradient {
        LinearGradient(colors: [.synapseCyan, .synapseBlue, .synapseIndigo],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension ConnectionStatus {
    var tint: Color {
        switch self {
        case .connected: return .green
        case .discovering, .connecting: return .orange
        case .pairing: return .synapseBlue
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    var title: String {
        switch self {
        case .connected: return "Bağlı"
        case .discovering: return "Bekliyor"
        case .connecting: return "Bağlanıyor"
        case .pairing: return "Eşleşiyor"
        case .disconnected: return "Çevrimdışı"
        case .error: return "Hata"
        }
    }
}

extension Locale {
    /// The UI text is Turkish; dates and relative times should match it.
    static let turkish = Locale(identifier: "tr_TR")
}

// MARK: - Background

/// Soft grey field behind the content: enough variation for the glass to refract,
/// without colour.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(macOS 15.0, *) {
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0, 0], [0.55, 0], [1, 0],
                        [0, 0.45], [0.6, 0.5], [1, 0.4],
                        [0, 1], [0.45, 1], [1, 1]
                    ],
                    colors: colorScheme == .dark ? Self.darkMesh : Self.lightMesh
                )
            } else {
                ZStack {
                    VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                    RadialGradient(colors: [Color.primary.opacity(0.08), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 520)
                    RadialGradient(colors: [Color.primary.opacity(0.06), .clear],
                                   center: .bottomTrailing, startRadius: 0, endRadius: 460)
                }
            }
        }
        .ignoresSafeArea()
    }

    private static let darkMesh: [Color] = [
        Color(hex: 0x1F1F22), Color(hex: 0x2C2C2F), Color(hex: 0x18181A),
        Color(hex: 0x252527), Color(hex: 0x0B0B0C), Color(hex: 0x27272A),
        Color(hex: 0x1A1A1C), Color(hex: 0x0F0F11), Color(hex: 0x222224)
    ]

    private static let lightMesh: [Color] = [
        Color(hex: 0xE9E9EC), Color(hex: 0xF7F7F9), Color(hex: 0xE3E3E7),
        Color(hex: 0xF1F1F4), Color(hex: 0xFBFBFC), Color(hex: 0xE8E8EC),
        Color(hex: 0xE1E1E5), Color(hex: 0xF4F4F6), Color(hex: 0xECECEF)
    ]
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Glass

extension View {
    /// Liquid Glass on macOS 26+, a material with a hairline edge before that.
    @ViewBuilder
    func glassSurface<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.background {
                ZStack {
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .clipShape(shape)
                    if let tint { shape.fill(tint.opacity(0.14)) }
                    shape.stroke(Color.white.opacity(0.16), lineWidth: 0.6)
                }
                .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
            }
        }
    }

    @available(macOS 26.0, *)
    private static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    /// System glass buttons on macOS 26+, bordered buttons before that.
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }

    /// Lets the background continue under the floating sidebar on macOS 26.
    @ViewBuilder
    func extendsUnderSidebar() -> some View {
        if #available(macOS 26.0, *) {
            self.backgroundExtensionEffect()
        } else {
            self
        }
    }
}

/// Lets neighbouring glass shapes blend into each other (macOS 26+).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Rounded glass panel for grouped content.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Subtle fill for rows inside a glass card (glass on glass is avoided).
struct InsetRowBackground: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content.background(Color.primary.opacity(0.05),
                           in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func insetRow(cornerRadius: CGFloat = 12) -> some View {
        modifier(InsetRowBackground(cornerRadius: cornerRadius))
    }
}

// MARK: - Brand

/// The Synapse hub: a centre node linked to three others.
struct HubGlyph: View {
    var color: Color = .white

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let reach = side * 0.36
            let node = side * 0.12
            let points = [-90.0, 30.0, 150.0].map { degrees in
                CGPoint(x: center.x + reach * cos(degrees * .pi / 180),
                        y: center.y + reach * sin(degrees * .pi / 180))
            }
            var links = Path()
            for point in points {
                links.move(to: center)
                links.addLine(to: point)
            }
            context.stroke(links, with: .color(color.opacity(0.85)), lineWidth: node * 0.7)
            for point in points + [center] {
                let dot = CGRect(x: point.x - node, y: point.y - node, width: node * 2, height: node * 2)
                context.fill(Path(ellipseIn: dot), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

struct SynapseMark: View {
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(.synapseGradient)
            .frame(width: size, height: size)
            .overlay { HubGlyph().padding(size * 0.18) }
            .shadow(color: Color.synapseBlue.opacity(0.35), radius: size * 0.15, y: size * 0.06)
            .accessibilityHidden(true)
    }
}

// MARK: - Small pieces

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.8), radius: 3)
    }
}

/// Icon in a tinted rounded tile, as in System Settings rows.
struct IconTile: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.synapseGradient)
                .frame(width: 72, height: 72)
                .background(Color.primary.opacity(0.05), in: Circle())
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

/// Card title with an icon, used at the top of glass cards.
struct CardHeader<Trailing: View>: View {
    let title: String
    let icon: String
    var tint: Color = .synapseBlue
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            IconTile(systemName: icon, color: tint, size: 28)
            Text(title).font(.headline)
            Spacer()
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, icon: String, tint: Color = .synapseBlue) {
        self.init(title: title, icon: icon, tint: tint) { EmptyView() }
    }
}
