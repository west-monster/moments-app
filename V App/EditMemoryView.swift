import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct EditMemoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var memory: Memory

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var currentPhotoIndex = 0
    @State private var message: String
    @State private var notes: String
    @State private var date: Date
    @State private var tag: MemoryTag
    @State private var cropOffsetX: CGFloat
    @State private var cropOffsetY: CGFloat
    @State private var dragStartX: CGFloat
    @State private var dragStartY: CGFloat
    @State private var appeared = false
    @State private var isSaving = false
    @State private var showSaveError = false
    @State private var didChangePhotos = false

    init(memory: Memory) {
        self.memory = memory
        _message = State(initialValue: memory.message)
        _notes = State(initialValue: memory.notes)
        _date = State(initialValue: memory.date)
        _tag = State(initialValue: MemoryTag(rawValue: memory.tag) ?? .none)
        _cropOffsetX = State(initialValue: CGFloat(memory.cropOffsetX))
        _cropOffsetY = State(initialValue: CGFloat(memory.cropOffsetY))
        _dragStartX = State(initialValue: CGFloat(memory.cropOffsetX))
        _dragStartY = State(initialValue: CGFloat(memory.cropOffsetY))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    photoSection
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
                        DatePicker(
                            String(localized: "form.date.pick"),
                            selection: $date,
                            in: ...Date.now,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(AppTheme.accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .disabled(isSaving)
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
                            currentPhotoIndex = 0
                            cropOffsetX = 0.5
                            cropOffsetY = 0.5
                            didChangePhotos = true
                        }
                    }
                }
            }
            .onAppear {
                images = memory.allImages
                withAnimation(.easeOut(duration: 0.4)) { appeared = true }
            }
            .alert(String(localized: "save.error.title"), isPresented: $showSaveError) {
                Button("OK") {}
            } message: {
                Text("save.error.message")
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
                                let imgW = img.size.width
                                let imgH = img.size.height
                                let aspect = imgW / imgH
                                let isPortrait = aspect < 1
                                let scaledW = isPortrait ? side : side * aspect
                                let scaledH = isPortrait ? side / aspect : side
                                let overflowX = max(scaledW - side, 0)
                                let overflowY = max(scaledH - side, 0)

                                Color.clear
                                    .overlay {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFill()
                                            .offset(
                                                x: index == 0 ? overflowX * (0.5 - cropOffsetX) : 0,
                                                y: index == 0 ? overflowY * (0.5 - cropOffsetY) : 0
                                            )
                                    }
                                    .frame(width: side, height: side)
                                    .clipped()
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 6, matching: .images) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                        .padding(10)
                    }

                    if images.count > 1 {
                        HStack(spacing: 5) {
                            ForEach(0..<images.count, id: \.self) { i in
                                Capsule()
                                    .fill(i == currentPhotoIndex ? AppTheme.accent : AppTheme.textSecondary.opacity(0.3))
                                    .frame(width: i == currentPhotoIndex ? 16 : 6, height: 6)
                                    .animation(.spring(response: 0.3), value: currentPhotoIndex)
                            }
                        }
                    }
                }
            } else {
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 6, matching: .images) {
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
                            .foregroundStyle(tag == t ? .white : AppTheme.textPrimary)
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
        isSaving = true

        if didChangePhotos && !images.isEmpty {
            for name in memory.allImageFileNames {
                LocalStore.shared.deleteImage(named: name)
            }

            guard let mainName = LocalStore.shared.saveImage(images[0]) else {
                isSaving = false
                showSaveError = true
                return
            }
            memory.imageFileName = mainName

            var extras: [String] = []
            for img in images.dropFirst() {
                if let name = LocalStore.shared.saveImage(img) {
                    extras.append(name)
                }
            }
            memory.extraImageFileNames = extras
        }

        memory.message = message
        memory.notes = notes
        memory.date = date
        memory.tag = tag.rawValue
        memory.cropOffsetX = Double(cropOffsetX)
        memory.cropOffsetY = Double(cropOffsetY)

        dismiss()
    }
}
