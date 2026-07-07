import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// A photo slot in the edit form. `fileName` is the file already on disk;
/// `nil` means the user just picked it and it only gets written on save.
/// The square-crop position (0...1, 0.5 = centered) travels with the photo.
private struct EditablePhoto: Identifiable {
    let id = UUID()
    var image: UIImage
    var fileName: String?
    var cropX: CGFloat = 0.5
    var cropY: CGFloat = 0.5
}

struct EditMemoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var memory: Memory

    @State private var photos: [EditablePhoto] = []
    @State private var draggedPhoto: EditablePhoto?
    /// Existing files the user replaced or removed; deleted from disk on save.
    @State private var removedFileNames: [String] = []
    @State private var additionItems: [PhotosPickerItem] = []
    /// Single-photo replacement: which slot, and the picked item.
    @State private var replaceIndex: Int?
    @State private var replaceItem: PhotosPickerItem?
    @State private var showReplacePicker = false
    @State private var cropTarget: PhotoCropTarget?
    @State private var name: String
    @State private var notes: String
    @State private var date: Date
    @State private var selectedCategory: MemoryTag
    @State private var isSaving = false
    @State private var showSaveError = false

    private let thumbColumns = [GridItem(.adaptive(minimum: 72), spacing: 8)]

    init(memory: Memory) {
        self.memory = memory
        _name = State(initialValue: memory.message)
        _notes = State(initialValue: memory.notes)
        _date = State(initialValue: memory.date)
        _selectedCategory = State(initialValue: MemoryTag(rawValue: memory.tag) ?? .none)
    }

    var body: some View {
        NavigationStack {
            Form {
                photosSection
                categorySection
                nameSection
                descriptionSection
                dateSection
            }
            .scrollContentBackground(.visible)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "form.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "form.save")) { save() }
                        .fontWeight(.semibold)
                        .disabled(photos.isEmpty || isSaving)
                }
            }
            .onChange(of: additionItems) { _, newValue in applyAdditions(newValue) }
            .photosPicker(isPresented: $showReplacePicker, selection: $replaceItem, matching: .images)
            .onChange(of: replaceItem) { _, newValue in applyReplacement(newValue) }
            .task { photos = await fetchPhotos() }
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
        .tint(AppTheme.accent)
    }

    // MARK: - Photos

    private var photosSubtitle: String {
        String(format: String(localized: "form.photos.subtitle"), MemoryLimits.maxPhotos)
    }

    @ViewBuilder
    private var photosSection: some View {
        Section {
            if photos.isEmpty {
                PhotosPicker(selection: $additionItems, maxSelectionCount: MemoryLimits.maxPhotos, matching: .images) {
                    choosePhotosPlaceholder
                }
            } else {
                PhotosPicker(
                    selection: $additionItems,
                    maxSelectionCount: max(MemoryLimits.maxPhotos - photos.count, 1),
                    matching: .images
                ) {
                    addMorePhotosRow
                }
                .disabled(photos.count >= MemoryLimits.maxPhotos)

                LazyVGrid(columns: thumbColumns, spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        Menu {
                            Button {
                                replaceIndex = index
                                showReplacePicker = true
                            } label: {
                                Label("photo.change", systemImage: "photo")
                            }
                            Button {
                                cropTarget = PhotoCropTarget(id: index)
                            } label: {
                                Label("photo.crop", systemImage: "crop")
                            }
                            Button(role: .destructive) {
                                removePhoto(at: index)
                            } label: {
                                Label("photo.remove", systemImage: "trash")
                            }
                        } label: {
                            thumbnail(photo)
                        }
                        .onDrag {
                            draggedPhoto = photo
                            return NSItemProvider(object: photo.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: PhotoReorderDropDelegate(item: photo, items: $photos, dragged: $draggedPhoto)
                        )
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    /// Prominent centered call-to-action shown when there are no photos.
    private var choosePhotosPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 30))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 84, height: 84)
                .background(Color(.systemGray5), in: Circle())

            Text("form.choosePhotos")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(photosSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    /// Compact row to add more photos.
    private var addMorePhotosRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.title2)
                .foregroundStyle(AppTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("form.addPhotos")
                    .foregroundStyle(AppTheme.accent)
                Text(photosSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func thumbnail(_ photo: EditablePhoto) -> some View {
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
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Category

    private var categorySection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MemoryTag.allCases) { category in
                        categoryChip(category)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color(.systemGroupedBackground))
        } header: {
            Text("form.section.category").textCase(nil)
        }
    }

    private func categoryChip(_ category: MemoryTag) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedCategory = category }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                Text(category == .none ? String(localized: "tag.none") : category.label)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? AppTheme.accent : Color(.secondarySystemGroupedBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Text fields

    private var nameSection: some View {
        Section {
            TextField(String(localized: "form.message.placeholder"), text: $name)
        } header: {
            Text("form.section.name").textCase(nil)
        }
    }

    private var descriptionSection: some View {
        Section {
            TextField(String(localized: "form.description.placeholder"), text: $notes, axis: .vertical)
                .lineLimit(3...6)
        } header: {
            Text("form.section.description").textCase(nil)
        }
    }

    private var dateSection: some View {
        Section {
            DatePicker(
                String(localized: "form.section.date"),
                selection: $date,
                in: ...Date.now,
                displayedComponents: .date
            )
        }
    }

    // MARK: - Photo operations

    /// Decodes the photos off the main thread, downsampled so a full memory
    /// (up to `MemoryLimits.maxPhotos`) doesn't exhaust memory or freeze the
    /// presentation.
    private func fetchPhotos() async -> [EditablePhoto] {
        let names = memory.allImageFileNames
        let crops = names.indices.map { memory.cropOffset(at: $0) }
        let loaded = await Task.detached(priority: .userInitiated) {
            names.enumerated().compactMap { index, name -> (String, UIImage, Int)? in
                LocalStore.shared.loadDownscaledImage(named: name, maxPixel: 1400).map { (name, $0, index) }
            }
        }.value
        return loaded.map { name, image, index in
            EditablePhoto(image: image, fileName: name, cropX: crops[index].x, cropY: crops[index].y)
        }
    }

    /// Appends the newly picked photos (up to the limit), then clears the
    /// picker selection so the next pick adds more.
    private func applyAdditions(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var loaded: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loaded.append(image)
                }
            }
            additionItems = []
            guard !loaded.isEmpty else { return }
            let room = max(MemoryLimits.maxPhotos - photos.count, 0)
            let toAdd = Array(loaded.prefix(room))
            guard !toAdd.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                photos.append(contentsOf: toAdd.map { EditablePhoto(image: $0, fileName: nil) })
            }
        }
    }

    /// Replaces a single photo (the one whose menu was used) with one new pick.
    private func applyReplacement(_ item: PhotosPickerItem?) {
        guard let item, let index = replaceIndex else { return }
        Task {
            defer {
                replaceItem = nil
                replaceIndex = nil
            }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  photos.indices.contains(index) else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                if let old = photos[index].fileName {
                    removedFileNames.append(old)
                }
                photos[index] = EditablePhoto(image: image, fileName: nil)
            }
        }
    }

    private func removePhoto(at index: Int) {
        guard photos.indices.contains(index) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            if let old = photos[index].fileName {
                removedFileNames.append(old)
            }
            photos.remove(at: index)
        }
    }

    // MARK: - Save

    private func save() {
        guard !photos.isEmpty else { return }
        isSaving = true

        var saved: [(name: String, cropX: CGFloat, cropY: CGFloat)] = []
        for photo in photos {
            if let existing = photo.fileName {
                saved.append((existing, photo.cropX, photo.cropY))
            } else if let newName = LocalStore.shared.saveImage(photo.image) {
                saved.append((newName, photo.cropX, photo.cropY))
            }
        }

        guard let first = saved.first else {
            isSaving = false
            showSaveError = true
            return
        }

        for fileName in removedFileNames {
            LocalStore.shared.deleteImage(named: fileName)
        }

        memory.imageFileName = first.name
        memory.cropOffsetX = Double(first.cropX)
        memory.cropOffsetY = Double(first.cropY)
        memory.extraImageFileNames = saved.dropFirst().map(\.name)
        memory.extraCropOffsetsX = saved.dropFirst().map { Double($0.cropX) }
        memory.extraCropOffsetsY = saved.dropFirst().map { Double($0.cropY) }
        memory.message = name
        memory.notes = notes
        memory.date = date
        memory.tag = selectedCategory.rawValue

        // Persist immediately so ContentView's save observer mirrors the edit
        // to the widget and watch without waiting for an autosave.
        try? memory.modelContext?.save()

        dismiss()
    }
}
