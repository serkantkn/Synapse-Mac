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
        GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 16)
    ]

    var body: some View {
        ZStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
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
                                    Color.black.opacity(0.5)
                                        .cornerRadius(12)
                                    ProgressView()
                                        .controlSize(.small)
                                        .colorScheme(.dark)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            
            if viewModel.remotePhotos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Fotoğraf Bulunamadı")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Bağlı cihazdan fotoğraflar yükleniyor...")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
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
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
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
                                HStack {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Bilgisayara Kaydet")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .modifier(GlassTintedBackground(cornerRadius: 8, tint: .blue))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.white)
                            
                            Button(action: {
                                let _ = viewModel.openInPreview(image: full, filename: selected.name)
                            }) {
                                HStack {
                                    Image(systemName: "eye")
                                    Text("Tekrar Önizleme ile Aç")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .modifier(GlassRowBackground(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.white)
                            
                            Button(action: {
                                photoToDelete = selected
                                showDeleteConfirmation = true
                            }) {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Telefondan Sil")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .modifier(GlassTintedBackground(cornerRadius: 8, tint: .red))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.white)
                        }
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
    
    var body: some View {
        VStack {
            if let thumb = photo.thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 120)
                    .clipped()
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .cornerRadius(8)
            }
            
            Text(photo.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(8)
        .modifier(GlassRowBackground(cornerRadius: 12))
    }
}
