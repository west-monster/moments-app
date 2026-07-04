import SwiftUI

struct SplashView: View {
    @Binding var showSplash: Bool
    let isFirstLaunch: Bool

    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 30
    @State private var subtitleOpacity: Double = 0
    @State private var lineWidth: CGFloat = 0
    @State private var labelOpacity: Double = 0
    @State private var chevronBounce: Bool = false
    @State private var dragOffset: CGFloat = 0

    /// Keeps the hero title at its designed size while still scaling with the
    /// user's Dynamic Type setting.
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 48

    private var topLabel: String {
        isFirstLaunch ? AlbumContent.dedicatoria : String(localized: "splash.welcomeBack")
    }

    private var mainTitle: String {
        isFirstLaunch ? AlbumContent.titulo : AlbumContent.tituloRecurrente
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                AppTheme.sectionTitle(topLabel)
                    .opacity(labelOpacity)

                Rectangle()
                    .fill(AppTheme.accent)
                    .frame(width: lineWidth, height: 2)

                HighlightHeadline(text: mainTitle, font: .system(size: titleSize, weight: .black), tracking: -2)
                    .opacity(titleOpacity)
                    .offset(y: titleOffset)

                Text("splash.swipeToDiscover")
                    .font(AppTheme.Font.chip)
                    .foregroundStyle(AppTheme.textSecondary)
                    .opacity(subtitleOpacity)
                    .padding(.top, 4)

                Spacer()

                Image(systemName: "chevron.compact.up")
                    .font(.title2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .opacity(subtitleOpacity)
                    .offset(y: chevronBounce ? -6 : 0)
                    .padding(.bottom, 50)
            }
            .padding(.horizontal, 24)
        }
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Only follow upward drags.
                    dragOffset = min(0, value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height < -80 {
                        dismissSplash()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onTapGesture { dismissSplash() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                labelOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.5)) {
                lineWidth = 50
            }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7, blendDuration: 0).delay(0.7)) {
                titleOpacity = 1
                titleOffset = 0
            }
            withAnimation(.easeOut(duration: 0.6).delay(1.4)) {
                subtitleOpacity = 1
            }
            withAnimation(.easeInOut(duration: 1.0).delay(1.8).repeatForever(autoreverses: true)) {
                chevronBounce = true
            }
        }
    }

    private func dismissSplash() {
        withAnimation(.easeOut(duration: 0.5)) {
            showSplash = false
        }
    }
}
