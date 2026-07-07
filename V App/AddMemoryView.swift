import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// A picked photo with a stable identity, so the grid can be reordered by drag.
private struct PickedPhoto: Identifiable {
    let id = UUID()
    var image: UIImage
    var crop: CGPoint = CGPoint(x: 0.5, y: 0.5)
}

struct AddMemoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photos: [PickedPhoto] = []
    @State private var draggedPhoto: PickedPhoto?
    @State private var cropTarget: PhotoCropTarget?
    /// Single-photo replacement: which slot (by id), and the picked item.
    @State private var replaceID: UUID?
    @State private var replaceItem: PhotosPickerItem?
    @State private var showReplacePicker = false
    @State private var name = ""
    @State private var notes = ""
    @State private var date = Date.now
    @State private var selectedCategory: MemoryTag = .none
    @State private var isSaving = false
    @State private var showSaveError = false
    var nextOrder: Int

    private let thumbColumns = [GridItem(.adaptive(minimum: 72), spacing: 8)]

    /// Save needs at least one photo or a name.
    private var canSave: Bool {
        !photos.isEmpty || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            .navigationTitle(String(localized: "form.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "form.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "form.save")) { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave || isSaving)
                }
            }
            .onChange(of: selectedPhotos) { _, newValue in loadPhotos(newValue) }
            .photosPicker(isPresented: $showReplacePicker, selection: $replaceItem, matching: .images)
            .onChange(of: replaceItem) { _, newValue in replacePhoto(newValue) }
            .alert(String(localized: "save.error.title"), isPresented: $showSaveError) {
                Button("OK") {}
            } message: {
                Text("save.error.message")
            }
            .sheet(item: $cropTarget) { target in
                if photos.indices.contains(target.id) {
                    CropAdjustView(image: photos[target.id].image, initialCrop: photos[target.id].crop) { newCrop in
                        if photos.indices.contains(target.id) {
                            photos[target.id].crop = newCrop
                        }
                    }
                }
            }
        }
        .tint(AppTheme.accent)
    }

    // MARK: - Choose Photos

    private var photosSubtitle: String {
        String(format: String(localized: "form.photos.subtitle"), MemoryLimits.maxPhotos)
    }

    @ViewBuilder
    private var photosSection: some View {
        Section {
            if photos.isEmpty {
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: MemoryLimits.maxPhotos, matching: .images) {
                    choosePhotosPlaceholder
                }
            } else {
                PhotosPicker(
                    selection: $selectedPhotos,
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
                                replaceID = photo.id
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
                                removePhoto(photo)
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

    /// Prominent centered call-to-action shown before any photo is picked.
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

    /// Compact row to add more photos once some are picked.
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

    private func thumbnail(_ photo: PickedPhoto) -> some View {
        GeometryReader { geo in
            let side = geo.size.width
            let crop = SquareCropGeometry(imageSize: photo.image.size, side: side)

            Color.clear
                .overlay {
                    Image(uiImage: photo.image)
                        .resizable()
                        .scaledToFill()
                        .offset(crop.offset(cropX: photo.crop.x, cropY: photo.crop.y))
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

    /// Appends the newly picked photos (never replaces the whole set), up to
    /// the per-memory limit, then clears the picker selection so the next pick
    /// adds more.
    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var loaded: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loaded.append(image)
                }
            }
            selectedPhotos = []
            guard !loaded.isEmpty else { return }
            let room = max(MemoryLimits.maxPhotos - photos.count, 0)
            let toAdd = Array(loaded.prefix(room))
            guard !toAdd.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                photos.append(contentsOf: toAdd.map { PickedPhoto(image: $0) })
            }
        }
    }

    /// Replaces a single photo (the one whose menu was used) with one new pick.
    private func replacePhoto(_ item: PhotosPickerItem?) {
        guard let item, let id = replaceID else { return }
        Task {
            defer {
                replaceItem = nil
                replaceID = nil
            }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let index = photos.firstIndex(where: { $0.id == id }) else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                photos[index].image = image
                photos[index].crop = CGPoint(x: 0.5, y: 0.5)
            }
        }
    }

    private func removePhoto(_ photo: PickedPhoto) {
        withAnimation(.easeInOut(duration: 0.25)) {
            photos.removeAll { $0.id == photo.id }
        }
    }

    // MARK: - Save

    private func save() {
        guard canSave else { return }
        isSaving = true

        var mainFileName = ""
        if let first = photos.first {
            guard let saved = LocalStore.shared.saveImage(first.image) else {
                isSaving = false
                showSaveError = true
                return
            }
            mainFileName = saved
        }

        var extraNames: [String] = []
        var extraXs: [Double] = []
        var extraYs: [Double] = []
        for photo in photos.dropFirst() {
            if let saved = LocalStore.shared.saveImage(photo.image) {
                extraNames.append(saved)
                extraXs.append(Double(photo.crop.x))
                extraYs.append(Double(photo.crop.y))
            }
        }

        let mainCrop = photos.first?.crop ?? CGPoint(x: 0.5, y: 0.5)
        let memory = Memory(
            imageFileName: mainFileName,
            message: name,
            notes: notes,
            date: date,
            order: nextOrder,
            cropOffsetX: Double(mainCrop.x),
            cropOffsetY: Double(mainCrop.y),
            tag: selectedCategory.rawValue,
            extraImageFileNames: extraNames,
            extraCropOffsetsX: extraXs,
            extraCropOffsetsY: extraYs
        )
        modelContext.insert(memory)
        dismiss()
    }
}
