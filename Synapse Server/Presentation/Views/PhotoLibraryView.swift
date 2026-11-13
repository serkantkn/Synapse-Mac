//
//  PhotoLibraryView.swift
//  Synapse Server
//
//  Displays the Android photo library in a grid.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PhotoLibraryView: View {
    @ObservedObject var viewModel: SynapseViewModel
    @State private var selectedPhoto: RemotePhoto? = nil
    @State private var downloadingPhotoId: String? = nil
    @State private var showDeleteConfirmation = false
    @State private var photoToDelete: RemotePhoto? = nil
    
    let columns = [
        GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 14)
    ]

    var body: some View {
        ZStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(viewModel.remotePhotos) { photo in
                        ZStack(alignment: .center) {
                            PhotoCell(photo: photo)
                                .onTapGesture {
                                    handlePhotoTap(photo)
                                }
                                .contextMenu {
                                    Button(action: { handlePhotoTap(photo) }) {
                                        Label("Aç (Önizleme)", systemImage: "eye")
                                    }
                                    
                                    if let full = photo.fullImage {
                                        Button(action: { saveImage(full, name: photo.name) }) {
                                            Label("Bilgisayara Kaydet...", systemImage: "square.and.arrow.down")
                                        }
                                    }
                                    
                                    Divider()
                                    
                                    Button(role: .destructive, action: {
                                        photoToDelete = photo
                                        showDeleteConfirmation = true
                                    }) {
                                        Label("Telefondan Sil", systemImage: "trash")
                                    }
                                }
                            
                            // Spinner inside the specific cell during download
                            if downloadingPhotoId == photo.id {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(.black.opacity(0.45))
                                    ProgressView()
                                        .controlSize(.small)
                                        .colorScheme(.dark)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
            
            if viewModel.remotePhotos.isEmpty {
                GlassCard {
                    VStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        EmptyStateView(icon: "photo.on.rectangle.angled", title: "Fotoğraflar yükleniyor",
                                       subtitle: "Telefondaki son fotoğraflar birazdan burada görünür.")
                    }
                }
                .frame(maxWidth: 420)
                .padding(28)
            }
            
            // Full Screen Fallback Overlay (If macOS Preview fails)
            if let selected = selectedPhoto {
                Color.black.opacity(0.85)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture { selectedPhoto = nil }
                
                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        Button(action: { selectedPhoto = nil }) {
                            Image(systemName: "xmark")
                                .font(.title3.weight(.semibold))
                                .frame(width: 22, height: 22)
                        }
                        .glassButtonStyle()
                        .controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                        .help("Kapat")
                        .padding()
                    }
                    
                    Spacer()
                    
                    if let full = selected.fullImage ?? viewModel.remotePhotos.first(where: { $0.id == selected.id })?.fullImage {
                        Image(nsImage: full)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        
                        // Control Panel below image
                        HStack(spacing: 20) {
                            Button(action: { saveImage(full, name: selected.name) }) {
                                Label("Mac'e Kaydet", systemImage: "square.and.arrow.down")
                            }
                            .glassButtonStyle(prominent: true)

                            Button(action: {
                                let _ = viewModel.openInPreview(image: full, filename: selected.name)
                            }) {
                                Label("Önizleme ile Aç", systemImage: "eye")
                            }
                            .glassButtonStyle()

                            Button(role: .destructive, action: {
                                photoToDelete = selected
                                showDeleteConfirmation = true
                            }) {
                                Label("Telefondan Sil", systemImage: "trash")
                            }
                            .glassButtonStyle()
                            .foregroundStyle(.red)
                        }
                        .controlSize(.large)
                        .padding(.bottom, 24)
                        
                    } else {
                        ProgressView()
                            .controlSize(.large)
                            .colorScheme(.dark)
                        Text("Yüksek çözünürlüklü fotoğraf indiriliyor...")
                            .foregroundColor(.white)
                            .padding(.top, 8)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            viewModel.requestPhotoLibrary()
        }
        .alert("Fotoğrafı Sil", isPresented: $showDeleteConfirmation, presenting: photoToDelete) { photo in
            Button("Sil", role: .destructive) {
                viewModel.deletePhotoFromPhone(id: photo.id)
                if selectedPhoto?.id == photo.id {
                    selectedPhoto = nil
                }
                photoToDelete = nil
            }
            Button("İptal", role: .cancel) {
                photoToDelete = nil
            }
        } message: { photo in
            Text("'\(photo.name)' adlı fotoğrafı telefonunuzdan silmek istediğinize emin misiniz? Bu işlem geri alınamaz.")
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PhotoDownloaded"))) { notification in
            if let userInfo = notification.userInfo,
               let id = userInfo["id"] as? String,
               let opened = userInfo["openedInPreview"] as? Bool {
                if downloadingPhotoId == id {
                    downloadingPhotoId = nil
                    if !opened {
                        // Failed to open with macOS Preview — fallback to our SwiftUI window!
                        selectedPhoto = viewModel.remotePhotos.first(where: { $0.id == id })
                    }
                }
            }
        }
    }
    
    private func handlePhotoTap(_ photo: RemotePhoto) {
        if let full = photo.fullImage {
            // Already downloaded, just attempt to open in Preview
            let opened = viewModel.openInPreview(image: full, filename: photo.name)
            if !opened {
                selectedPhoto = photo
            }
        } else {
            // Download it
            downloadingPhotoId = photo.id
            viewModel.downloadFullPhoto(id: photo.id)
        }
    }
    
    private func saveImage(_ image: NSImage, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [.jpeg]
        
        if panel.runModal() == .OK, let url = panel.url {
            if let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let data = bitmap.representation(using: .jpeg, properties: [:]) {
                try? data.write(to: url)
            }
        }
    }
}

struct PhotoCell: View {
    let photo: RemotePhoto
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let thumb = photo.thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .overlay { Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary) }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(isHovered ? 0.3 : 0.12), radius: isHovered ? 12 : 6, y: isHovered ? 6 : 3)

            Text(photo.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 2)
        }
        .scaleEffect(isHovered ? 1.03 : 1)
        .animation(.smooth(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
    }
}
