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
    @State private var cropOffsetX: CGFloat = 0.5
    @State private var cropOffsetY: CGFloat = 0.5
    @State private var dragStartX: CGFloat = 0.5
    @State private var dragStartY: CGFloat = 0.5
    var nextOrder: Int

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    photoSection
                    tagPicker

                    fieldCard(label: String(localized: "form.message")) {
                        TextField(String(localized: "form.message.placeholder"), text: $message, axis: .vertical)
                            .font(.system(size: 17, weight: .regular, design: .serif))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(3...6)
                            .tint(AppTheme.accent)
                    }

                    fieldCard(label: String(localized: "form.description")) {
                        TextField(String(localized: "form.description.placeholder"), text: $notes, axis: .vertical)
                            .font(.system(size: 15, weight: .regular, design: .serif))
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
            .navigationTitle(String(localized: "form.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "form.cancel")) { dismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "form.save")) { save() }
                        .font(.system(size: 16, weight: .bold))
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
                            currentPhotoIndex = 0
                            cropOffsetX = 0.5
                            cropOffsetY = 0.5
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
                    .gesture(
                        currentPhotoIndex == 0 ?
                        DragGesture()
                            .onChanged { value in
                                let img = images[0]
                                let aspect = img.size.width / img.size.height
                                let isPortrait = aspect < 1
                                let side: CGFloat = UIScreen.main.bounds.width - 32
                                let scaledW = isPortrait ? side : side * aspect
                                let scaledH = isPortrait ? side / aspect : side
                                let overflowX = max(scaledW - side, 0)
                                let overflowY = max(scaledH - side, 0)
                                if overflowX > 0 {
                                    let dx = -value.translation.width / overflowX
                                    cropOffsetX = min(max(dragStartX + dx, 0), 1)
                                }
                                if overflowY > 0 {
                                    let dy = -value.translation.height / overflowY
                                    cropOffsetY = min(max(dragStartY + dy, 0), 1)
                                }
                            }
                            .onEnded { _ in
                                dragStartX = cropOffsetX
                                dragStartY = cropOffsetY
                            }
                        : nil
                    )
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
                        photoIndicator
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
                                    .font(.system(size: 13, weight: .medium))
                                    .tracking(1)
                                    .textCase(.uppercase)
                            }
                            .foregroundStyle(AppTheme.textSecondary)
                        }
                }
            }
        }
    }

    private var photoIndicator: some View {
        HStack(spacing: 5) {
            ForEach(0..<images.count, id: \.self) { i in
                Capsule()
                    .fill(i == currentPhotoIndex ? AppTheme.accent : AppTheme.textSecondary.opacity(0.3))
                    .frame(width: i == currentPhotoIndex ? 16 : 6, height: 6)
                    .animation(.spring(response: 0.3), value: currentPhotoIndex)
            }
        }
    }

    // MARK: - Tag picker

    private var tagPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("form.tag")
                .font(.system(size: 11, weight: .bold))
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
                                    .font(.system(size: 12))
                                Text(t.label)
                                    .font(.system(size: 13, weight: .medium))
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
                .font(.system(size: 11, weight: .bold))
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
        for img in images.dropFirst() {
            if let name = LocalStore.shared.saveImage(img) {
                extraNames.append(name)
            }
        }

        let memory = Memory(
            imageFileName: mainFileName,
            message: message,
            notes: notes,
            date: date,
            order: nextOrder,
            cropOffsetX: Double(cropOffsetX),
            cropOffsetY: Double(cropOffsetY),
            tag: tag.rawValue,
            extraImageFileNames: extraNames
        )
        modelContext.insert(memory)
        dismiss()
    }
}
