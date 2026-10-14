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
    /// Single-photo replacement: which slot (by id), and the picked item.
    @State private var replaceID: UUID?
    @State private var replaceItem: PhotosPickerItem?
    @State private var showReplacePicker = false
    @State private var cropTarget: PhotoCropTarget?
    @State private var name: String
    @State private var notes: String
    @State private var date: Date
    @State private var selectedCategory: MemoryTag
    @State private var isSaving = false
    @State private var showSaveError = false
    @FocusState private var focusedField: MemoryFormField?
    /// Set once the existing photos have been decoded, so the initial load can
    /// never overwrite photos the user picked while it was still running.
    @State private var didLoadPhotos = false

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
            ScrollViewReader { proxy in
                Form {
                    photosSection
                    CategoryFormSection(selected: $selectedCategory)
                    nameSection
                    descriptionSection
                    dateSection
                }
                // Matches the add form: tighter section gaps so the fields fit
                // without scrolling on a standard phone.
                .listSectionSpacing(.compact)
                .scrollDismissesKeyboard(.interactively)
                .scrollsFocusedFieldAboveKeyboard(focusedField, revision: notes, in: proxy)
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
                .task {
                    guard !didLoadPhotos else { return }
                    let loaded = await fetchPhotos()
                    guard !didLoadPhotos else { return }
                    didLoadPhotos = true
                    // Photos the user picked while the decode was still running are
                    // kept and appended after the memory's existing ones, instead
                    // of being overwritten by the load.
                    photos = Array((loaded + photos).prefix(MemoryLimits.maxPhotos))
                }
                .alert(String(localized: "save.error.title"), isPresented: $showSaveError) {
                    Button("OK") {}
                } message: {
                    Text("save.error.message")
                }
                .sheet(item: $cropTarget) { target in
                    if let index = photos.firstIndex(where: { $0.id == target.id }) {
                        CropAdjustView(
                            image: photos[index].image,
                            initialCrop: CGPoint(x: photos[index].cropX, y: photos[index].cropY)
                        ) { newCrop in
                            // Resolved again on commit — the grid may have been
                            // reordered while the editor was open.
                            guard let current = photos.firstIndex(where: { $0.id == target.id }) else { return }
                            photos[current].cropX = newCrop.x
                            photos[current].cropY = newCrop.y
                        }
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
                    ForEach(photos) { photo in
                        Menu {
                            Button {
                                replaceID = photo.id
                                showReplacePicker = true
                            } label: {
                                Label("photo.change", systemImage: "photo")
                            }
                            Button {
                                cropTarget = PhotoCropTarget(id: photo.id)
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

    // MARK: - Text fields

    private var nameSection: some View {
        Section {
            TextField(String(localized: "form.message.placeholder"), text: $name)
                .focused($focusedField, equals: .name)
                .submitLabel(.next)
                .onSubmit { focusedField = .notes }
        } header: {
            Text("form.section.name").textCase(nil)
        }
        .id(MemoryFormField.name)
    }

    private var descriptionSection: some View {
        Section {
            TextField(String(localized: "form.description.placeholder"), text: $notes, axis: .vertical)
                .lineLimit(2...6)
                .focused($focusedField, equals: .notes)
        } header: {
            Text("form.section.description").textCase(nil)
        }
        .id(MemoryFormField.notes)
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
                if let old = photos[index].fileName {
                    removedFileNames.append(old)
                }
                photos[index] = EditablePhoto(image: image, fileName: nil)
            }
        }
    }

    private func removePhoto(_ photo: EditablePhoto) {
        guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
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

        let current = photos
        let removed = removedFileNames
        Task {
            // Only the newly picked photos need encoding — the existing ones
            // keep their file — and that encoding stays off the main thread.
            let newImages = current.filter { $0.fileName == nil }.map(\.image)
            let newNames = await Task.detached(priority: .userInitiated) {
                newImages.map { LocalStore.shared.saveImage($0) }
            }.value

            var newNameIterator = newNames.makeIterator()
            var saved: [(name: String, cropX: CGFloat, cropY: CGFloat)] = []
            for photo in current {
                if let existing = photo.fileName {
                    saved.append((existing, photo.cropX, photo.cropY))
                } else if let newName = newNameIterator.next() ?? nil {
                    saved.append((newName, photo.cropX, photo.cropY))
                }
            }

            guard let first = saved.first else {
                isSaving = false
                showSaveError = true
                return
            }

            let deletions = removed
            Task.detached(priority: .utility) {
                for fileName in deletions {
                    LocalStore.shared.deleteImage(named: fileName)
                }
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
}
