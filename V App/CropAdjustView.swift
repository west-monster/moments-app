import SwiftUI
import UIKit

/// Identifies which photo of a form carousel is being framed.
///
/// Carries the photo's own id, not its position: the grid can be reordered by
/// drag while the crop editor is open, and a stored index would then point at
/// whichever photo had slid into that slot.
struct PhotoCropTarget: Identifiable {
    let id: UUID
}

/// Drag-and-drop reordering for a grid of identifiable items. As the dragged
/// item passes over another, the array is reordered live.
struct PhotoReorderDropDelegate<Item: Identifiable>: DropDelegate {
    let item: Item
    @Binding var items: [Item]
    @Binding var dragged: Item?

    func dropEntered(info: DropInfo) {
        guard let dragged,
              dragged.id != item.id,
              let from = items.firstIndex(where: { $0.id == dragged.id }),
              let to = items.firstIndex(where: { $0.id == item.id })
        else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}

/// Dedicated square-framing editor. The photo pans freely under the frame —
/// no carousel paging to compete with — with a rule-of-thirds grid for
/// reference. The crop is committed only on "Done".
struct CropAdjustView: View {
    let image: UIImage
    let onDone: (CGPoint) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var crop: CGPoint
    @State private var dragStart: CGPoint

    init(image: UIImage, initialCrop: CGPoint, onDone: @escaping (CGPoint) -> Void) {
        self.image = image
        self.onDone = onDone
        _crop = State(initialValue: initialCrop)
        _dragStart = State(initialValue: initialCrop)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                GeometryReader { geo in
                    let side = geo.size.width
                    let geometry = SquareCropGeometry(imageSize: image.size, side: side)

                    Color.clear
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .offset(geometry.offset(cropX: crop.x, cropY: crop.y))
                        }
                        .frame(width: side, height: side)
                        .clipped()
                        .overlay { thirdsGrid }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let position = geometry.cropPosition(startX: dragStart.x, startY: dragStart.y, translation: value.translation)
                                    crop = CGPoint(x: position.x, y: position.y)
                                }
                                .onEnded { _ in dragStart = crop }
                        )
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("form.dragToAdjust")
                    .font(AppTheme.Font.chip)
                    .foregroundStyle(AppTheme.textSecondary)

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        crop = CGPoint(x: 0.5, y: 0.5)
                        dragStart = crop
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.backward.and.arrow.up.forward.circle")
                            .font(AppTheme.Font.chip)
                        Text("crop.center")
                            .font(AppTheme.Font.chip)
                    }
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
                    .background(AppTheme.accent.opacity(0.12), in: Capsule())
                }

                Spacer()
            }
            .padding(16)
            .frame(maxWidth: AppTheme.Layout.formMaxWidth)
            .frame(maxWidth: .infinity)
            .background(AppTheme.background)
            .navigationTitle(String(localized: "crop.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "form.cancel")) { dismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "crop.done")) {
                        onDone(crop)
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
                }
            }
        }
    }

    /// Rule-of-thirds reference lines over the frame.
    private var thirdsGrid: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                    path.move(to: CGPoint(x: w * fraction, y: 0))
                    path.addLine(to: CGPoint(x: w * fraction, y: h))
                    path.move(to: CGPoint(x: 0, y: h * fraction))
                    path.addLine(to: CGPoint(x: w, y: h * fraction))
                }
            }
            .stroke(.white.opacity(0.4), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}
