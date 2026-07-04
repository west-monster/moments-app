import SwiftUI

/// Vertically paged memory cards — the watchOS pattern for browsing
/// full-screen content (one memory per page, Digital Crown scrolls).
struct WatchContentView: View {
    @EnvironmentObject private var store: WatchMemoryStore
    @State private var selection = 0

    var body: some View {
        Group {
            if store.memories.isEmpty {
                emptyView
            } else {
                TabView(selection: $selection) {
                    ForEach(Array(store.memories.enumerated()), id: \.element.id) { index, memory in
                        WatchMemoryCard(memory: memory, image: store.images[memory.id])
                            .tag(index)
                    }
                }
                .tabViewStyle(.verticalPage)
            }
        }
        .onChange(of: store.memories) { _, newValue in
            if selection >= newValue.count {
                selection = max(0, newValue.count - 1)
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart.circle")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(.tint)
            Text("watch.empty")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }
}

/// One full-screen memory: edge-to-edge photo with a bottom scrim so the
/// message and date stay legible (HIG: text over photos needs a gradient).
struct WatchMemoryCard: View {
    let memory: WatchMemory
    let image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(.tint.opacity(0.15))
                        .overlay {
                            Image(systemName: "heart.circle")
                                .font(.system(size: 30, weight: .thin))
                                .foregroundStyle(.tint)
                        }
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.75)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 3) {
                    if !memory.message.isEmpty {
                        Text(memory.message)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                    Text(memory.date)
                        .font(.caption2)
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
        }
        .ignoresSafeArea()
    }
}
