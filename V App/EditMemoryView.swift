import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// A photo slot in the edit form. `fileName` is the file already on disk;
/// `nil` means the user just picked it and it only gets written on save.
/// The square-crop position (0...1, 0.5 = centered) travels with the photo.
private struct EditablePhoto: Identifiable {
    let id = UUID()
    var image: UIImage
    var fileName: String?
    var cropX: CGFloat = 0.5
    var cropY: CGFloat = 0.5

    var isNew: Bool { fileName == nil }
}

struct EditMemoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var memory: Memory

    @State private var photos: [EditablePhoto] = []
    /// Existing files the user replaced or removed; deleted from disk on save.
    @State private var removedFileNames: [String] = []
    @State private var replacementItems: [PhotosPickerItem] = []
    @State private var additionItems: [PhotosPickerItem] = []
    @State private var currentPhotoIndex = 0
    @State private var message: String
    @State private var notes: String
    @State private var date: Date
    @State private var tag: MemoryTag
    @State private var cropTarget: PhotoCropTarget?
    @State private var appeared = false
    @State private var isSaving = false
    @State private var showSaveError = false

    init(memory: Memory) {
        self.memory = memory
        _message = State(initialValue: memory.message)
        _notes = State(initialValue: memory.notes)
        _date = State(initialValue: memory.date)
        _tag = State(initialValue: MemoryTag(rawValue: memory.tag) ?? .none)
    }

    private var hasPhotoChanges: Bool {
        !removedFileNames.isEmpty || photos.contains(where: \.isNew)
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
            .navigationTitle(String(localized: "edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "form.cancel")) { dismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "form.save")) { save() }
                        .font(.headline)
                        .foregroundStyle(AppTheme.accent)
                        .disabled(isSaving || photos.isEmpty)
                }
            }
            .onChange(of: replacementItems) { _, newValue in
                applyReplacement(newValue)
            }
            .onChange(of: additionItems) { _, newValue in
                applyAdditions(newValue)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) { appeared = true }
            }
            .task {
                photos = await fetchPhotos()
            }
            .alert(String(localized: "save.error.title"), isPresented: $showSaveError) {
                Button("OK") {}
            } message: {
                Text("save.error.message")
            }
            .sheet(item: $cropTarget) { target in
                if photos.indices.contains(target.id) {
                    CropAdjustView(
                        image: photos[target.id].image,
                        initialCrop: CGPoint(x: photos[target.id].cropX, y: photos[target.id].cropY)
                    ) { newCrop in
                        guard photos.indices.contains(target.id) else { return }
                        photos[target.id].cropX = newCrop.x
                        photos[target.id].cropY = newCrop.y
                    }
                }
            }
        }
    }

    // MARK: - Photo section

    private var photoSection: some View {
        ZStack {
            if !photos.isEmpty {
                VStack(spacing: 10) {
                    TabView(selection: $currentPhotoIndex) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            GeometryReader { geo in
                                let side = geo.size.width
                                let crop = SquareCropGeometry(imageSize: photo.image.size, side: side)

                                Color.clear
                                    .overlay {
                                        Image(uiImage: photo.image)
                                            .resizable()
                                            .scaledToFill()
                                            .offset(crop.offset(cropX: photo.cropX, cropY: photo.cropY))
                                    }
                                    .frame(width: side, height: side)
                                    .clipped()
                                    .overlay(alignment: .topLeading) {
                                        PhotoCropButton { cropTarget = PhotoCropTarget(id: index) }
                                            .padding(6)
                                    }
                                    .overlay(alignment: .topTrailing) {
                                        if photo.isNew {
                                            newPhotoBadge
                                        }
                                    }
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if photos.count > 1 {
                        PhotoPageIndicator(count: photos.count, current: currentPhotoIndex)
                    }

                    photoActions

                    if hasPhotoChanges {
                        photosChangedNotice
                    }
                }
            } else {
                PhotosPicker(selection: $additionItems, maxSelectionCount: MemoryLimits.maxPhotos, matching: .images) {
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

    private var newPhotoBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
            Text("edit.newPhotos.badge")
                .font(AppTheme.Font.caption)
                .tracking(1)
                .textCase(.uppercase)
        }
        .foregroundStyle(AppTheme.onAccent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.accent, in: Capsule())
        .padding(10)
        .transition(.scale.combined(with: .opacity))
    }

    /// Per-photo actions: replace the photo on screen, append more, or remove
    /// the one on screen. Each acts on `currentPhotoIndex`, never on the
    /// whole set.
    private var photoActions: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $replacementItems, maxSelectionCount: 1, matching: .images) {
                photoActionLabel("arrow.triangle.2.circlepath", "edit.replacePhoto")
            }

            PhotosPicker(
                selection: $additionItems,
                maxSelectionCount: max(MemoryLimits.maxPhotos - photos.count, 0),
                matching: .images
            ) {
                photoActionLabel("plus", "edit.addPhotos")
            }
            .disabled(photos.count >= MemoryLimits.maxPhotos)

            Button {
                deleteCurrentPhoto()
            } label: {
                photoActionLabel("trash", "edit.deletePhoto")
            }
            .disabled(photos.count <= 1)
        }
    }

    private func photoActionLabel(_ icon: String, _ titleKey: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
            Text(titleKey)
                .font(AppTheme.Font.caption)
                .lineLimit(1)
        }
        .foregroundStyle(AppTheme.accent)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.cardBackground))
    }

    /// Shown only while there are unsaved photo changes: explains they apply
    /// on save, and offers a way back to the originals.
    private var photosChangedNotice: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(AppTheme.Font.chip)
                    .foregroundStyle(AppTheme.accent)
                Text("edit.photosWillReplace")
                    .font(AppTheme.Font.chip)
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                revertPhotos()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(AppTheme.Font.chip)
                    Text("edit.revertPhotos")
                        .font(AppTheme.Font.chip)
                }
                .foregroundStyle(AppTheme.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(AppTheme.accent.opacity(0.12), in: Capsule())
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.cardBackground))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Photo operations

    /// Decodes the photos off the main thread so opening the sheet with a
    /// full memory (up to `MemoryLimits.maxPhotos`) doesn't freeze the
    /// presentation animation.
    private func fetchPhotos() async -> [EditablePhoto] {
        let names = memory.allImageFileNames
        let crops = names.indices.map { memory.cropOffset(at: $0) }
        let loaded = await Task.detached(priority: .userInitiated) {
            names.enumerated().compactMap { index, name -> (String, UIImage, Int)? in
                LocalStore.shared.loadImage(named: name).map { (name, $0, index) }
            }
        }.value
        return loaded.map { name, image, index in
            EditablePhoto(image: image, fileName: name, cropX: crops[index].x, cropY: crops[index].y)
        }
    }

    private func applyReplacement(_ items: [PhotosPickerItem]) {
        guard let item = items.first else { return }
        Task {
            defer { replacementItems = [] }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  photos.indices.contains(currentPhotoIndex) else { return }

            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                if let old = photos[currentPhotoIndex].fileName {
                    removedFileNames.append(old)
                }
                photos[currentPhotoIndex] = EditablePhoto(image: image, fileName: nil)
            }
        }
    }

    private func applyAdditions(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            defer { additionItems = [] }
            var loaded: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loaded.append(image)
                }
            }
            guard !loaded.isEmpty else { return }

            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                let firstNewIndex = photos.count
                let room = max(MemoryLimits.maxPhotos - photos.count, 0)
                photos.append(contentsOf: loaded.prefix(room).map { EditablePhoto(image: $0, fileName: nil) })
                if photos.indices.contains(firstNewIndex) {
                    currentPhotoIndex = firstNewIndex
                }
            }
        }
    }

    private func deleteCurrentPhoto() {
        guard photos.count > 1, photos.indices.contains(currentPhotoIndex) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if let old = photos[currentPhotoIndex].fileName {
                removedFileNames.append(old)
            }
            photos.remove(at: currentPhotoIndex)
            currentPhotoIndex = min(currentPhotoIndex, photos.count - 1)
        }
    }

    private func revertPhotos() {
        replacementItems = []
        additionItems = []
        Task {
            let restored = await fetchPhotos()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                photos = restored
                removedFileNames = []
                currentPhotoIndex = 0
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
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.cardBackground))
    }

    // MARK: - Save

    private func save() {
        guard !photos.isEmpty else { return }
        isSaving = true

        var saved: [(name: String, cropX: CGFloat, cropY: CGFloat)] = []
        for photo in photos {
            if let existing = photo.fileName {
                saved.append((existing, photo.cropX, photo.cropY))
            } else if let name = LocalStore.shared.saveImage(photo.image) {
                saved.append((name, photo.cropX, photo.cropY))
            }
        }

        guard let first = saved.first else {
            isSaving = false
            showSaveError = true
            return
        }

        for name in removedFileNames {
            LocalStore.shared.deleteImage(named: name)
        }

        memory.imageFileName = first.name
        memory.cropOffsetX = Double(first.cropX)
        memory.cropOffsetY = Double(first.cropY)
        memory.extraImageFileNames = saved.dropFirst().map(\.name)
        memory.extraCropOffsetsX = saved.dropFirst().map { Double($0.cropX) }
        memory.extraCropOffsetsY = saved.dropFirst().map { Double($0.cropY) }
        memory.message = message
        memory.notes = notes
        memory.date = date
        memory.tag = tag.rawValue

        // Persist immediately so ContentView's save observer mirrors the edit
        // to the widget and watch without waiting for an autosave.
        try? memory.modelContext?.save()

        dismiss()
    }
}
