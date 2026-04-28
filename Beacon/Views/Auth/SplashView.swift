import SwiftUI

struct SplashView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Theme.Palette.deepTeal.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.l) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.white)
                    .scaleEffect(pulse ? 1.05 : 0.95)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                               value: pulse)

                Text("Beacon")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .padding(.top, Theme.Spacing.m)
            }
        }
        .onAppear { pulse = true }
    }
}

#Preview("SplashView") {
    SplashView()
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}
