import SwiftUI

/// Original light artwork, shared by the native Focus canvases. Its restrained
/// luminance cycle is ambient only and never expresses time or progress.
public struct DistantHorizonBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var illuminated = false

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Atmosphere.canvas.field
                HorizonArtwork.image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .offset(y: size.height * 0.07)
                    .opacity(illuminated ? 1 : 0.94)
                    .animation(
                        ambientMotion ? .easeInOut(duration: 14).repeatForever(autoreverses: true) : nil,
                        value: illuminated
                    )
                LinearGradient(
                    stops: [
                        .init(color: Atmosphere.canvas.field.opacity(0.55), location: 0),
                        .init(color: .clear, location: 0.43),
                        .init(color: .clear, location: 0.73),
                        .init(color: Atmosphere.canvas.field.opacity(0.65), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear { illuminated = ambientMotion }
        .onChange(of: ambientMotion) { _, active in illuminated = active }
    }

    private var ambientMotion: Bool {
        !reduceMotion && scenePhase == .active
    }
}
