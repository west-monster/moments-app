import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct AddMemoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var currentPhotoIndex = 0
    @State private var message = ""
    @State private var notes = ""
    @State private var date = Date.now
    @State private var tag: MemoryTag = .none
    @State private var appeared = false
    @State private var isSaving = false
    @State private var showSaveError = false
    /// Square-crop position per photo, aligned with `images`. Adjusted only
    /// through the per-photo crop editor, never by dragging the carousel.
    @State private var cropOffsets: [CGPoint] = []
    @State private var cropTarget: PhotoCropTarget?
    var nextOrder: Int

    private func cropOffset(at index: Int) -> CGPoint {
        cropOffsets.indices.contains(index) ? cropOffsets[index] : CGPoint(x: 0.5, y: 0.5)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    photoSection
                        .frame(maxWidth: 460)
                    tagPicker

                    fieldCard(label: String(localized: "form.message")) {
                        TextField(String(localized: "form.message.placeholder"), text: $message, axis: .vertical)
                            .font(AppTheme.Font.field)
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(3...6)
                            .tint(AppTheme.accent)
                    }

                    fieldCard(label: String(localized: "form.description")) {
                        TextField(String(localized: "form.description.placeholder"), text: $notes, axis: .vertical)
                            .font(AppTheme.Font.field)
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(3...8)
                            .tint(AppTheme.accent)
                    }

                    fieldCard(label: String(localized: "form.date")) {
                        FormDateField(date: $date)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: AppTheme.Layout.formMaxWidth)
                .frame(maxWidth: .infinity)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background)
            .navigationTitle(String(localized: "form.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "form.cancel")) { dismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "form.save")) { save() }
                        .font(.headline)
                        .foregroundStyle(!images.isEmpty ? AppTheme.accent : AppTheme.textSecondary)
                        .disabled(images.isEmpty || isSaving)
                }
            }
            .onChange(of: selectedPhotos) { _, newValue in
                Task {
                    var loaded: [UIImage] = []
                    for item in newValue {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            loaded.append(image)
                        }
                    }
                    if !loaded.isEmpty {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            images = loaded
                            cropOffsets = Array(repeating: CGPoint(x: 0.5, y: 0.5), count: loaded.count)
                            currentPhotoIndex = 0
                        }
                    }
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) { appeared = true }
            }
            .alert(String(localized: "save.error.title"), isPresented: $showSaveError) {
                Button("OK") {}
            } message: {
                Text("save.error.message")
            }
            .sheet(item: $cropTarget) { target in
                if images.indices.contains(target.id) {
                    CropAdjustView(image: images[target.id], initialCrop: cropOffset(at: target.id)) { newCrop in
                        if cropOffsets.indices.contains(target.id) {
                            cropOffsets[target.id] = newCrop
                        }
                    }
                }
            }
        }
    }

    // MARK: - Photo section

    private var photoSection: some View {
        ZStack {
            if !images.isEmpty {
                VStack(spacing: 10) {
                    TabView(selection: $currentPhotoIndex) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, img in
                            GeometryReader { geo in
                                let side = geo.size.width
                                let crop = SquareCropGeometry(imageSize: img.size, side: side)
                                let position = cropOffset(at: index)

                                Color.clear
                                    .overlay {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFill()
                                            .offset(crop.offset(cropX: position.x, cropY: position.y))
                                    }
                                    .frame(width: side, height: side)
                                    .clipped()
                                    .overlay(alignment: .topLeading) {
                                        PhotoCropButton { cropTarget = PhotoCropTarget(id: index) }
                                            .padding(6)
                                    }
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        PhotosPicker(selection: $selectedPhotos, maxSelectionCount: MemoryLimits.maxPhotos, matching: .images) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("form.changePhotos")
                                    .font(AppTheme.Font.chip)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(.black.opacity(0.5), in: Capsule())
                        }
                        .padding(10)
                    }

                    if images.count > 1 {
                        PhotoPageIndicator(count: images.count, current: currentPhotoIndex)
                    }
                }
            } else {
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: MemoryLimits.maxPhotos, matching: .images) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.cardBackground)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 40, weight: .thin))
                                Text("form.choosePhotos")
                                    .font(AppTheme.Font.chip)
                                    .tracking(1)
                                    .textCase(.uppercase)
                            }
                            .foregroundStyle(AppTheme.textSecondary)
                        }
                }
            }
        }
    }

    // MARK: - Tag picker

    private var tagPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("form.tag")
                .font(AppTheme.Font.eyebrow)
                .tracking(2)
                .foregroundStyle(AppTheme.accent)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MemoryTag.allCases) { t in
                        Button {
                            withAnimation(.spring(response: 0.3)) { tag = t }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: t.icon)
                                    .font(AppTheme.Font.chip)
                                Text(t.label)
                                    .font(AppTheme.Font.chip)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(tag == t ? AppTheme.onAccent : AppTheme.textPrimary)
                            .background(tag == t ? AppTheme.accent : AppTheme.cardBackground, in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.cardBackground))
    }

    private func fieldCard<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(AppTheme.Font.eyebrow)
                .tracking(2)
                .foregroundStyle(AppTheme.accent)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
    }

    // MARK: - Guardar

    private func save() {
        guard !images.isEmpty else { return }
        isSaving = true

        guard let mainFileName = LocalStore.shared.saveImage(images[0]) else {
            isSaving = false
            showSaveError = true
            return
        }

        var extraNames: [String] = []
        var extraXs: [Double] = []
        var extraYs: [Double] = []
        for (index, img) in images.enumerated().dropFirst() {
            if let name = LocalStore.shared.saveImage(img) {
                extraNames.append(name)
                let crop = cropOffset(at: index)
                extraXs.append(Double(crop.x))
                extraYs.append(Double(crop.y))
            }
        }

        let mainCrop = cropOffset(at: 0)
        let memory = Memory(
            imageFileName: mainFileName,
            message: message,
            notes: notes,
            date: date,
            order: nextOrder,
            cropOffsetX: Double(mainCrop.x),
            cropOffsetY: Double(mainCrop.y),
            tag: tag.rawValue,
            extraImageFileNames: extraNames,
            extraCropOffsetsX: extraXs,
            extraCropOffsetsY: extraYs
        )
        modelContext.insert(memory)
        dismiss()
    }
}
