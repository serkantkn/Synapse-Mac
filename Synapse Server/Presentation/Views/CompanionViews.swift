//
//  CompanionViews.swift
//  Synapse Server
//
//  Now playing, quick actions (find phone, send file/link) and notification reply UI.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Now Playing

struct NowPlayingCard: View {
    @ObservedObject var viewModel: SynapseViewModel
    var compact = false

    var body: some View {
        if let media = viewModel.media {
            let artSize: CGFloat = compact ? 44 : 72
            HStack(spacing: compact ? 10 : 16) {
                Group {
                    if let art = media.art {
                        Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            LinearGradient(colors: [.synapseCyan.opacity(0.5), .synapseIndigo.opacity(0.6)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                            Image(systemName: "music.note").font(.system(size: artSize * 0.4)).foregroundStyle(.white)
                        }
                    }
                }
                .frame(width: artSize, height: artSize)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 9 : 14, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: compact ? 4 : 10, y: compact ? 2 : 5)

                VStack(alignment: .leading, spacing: 3) {
                    if !compact {
                        Text("ŞİMDİ ÇALIYOR")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(media.title.isEmpty ? "Bilinmeyen parça" : media.title)
                        .font(.system(size: compact ? 12 : 15, weight: .semibold)).lineLimit(1)
                    Text([media.artist, media.appName].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: compact ? 10 : 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)

                HStack(spacing: compact ? 6 : 10) {
                    mediaButton("backward.fill", "PREVIOUS", help: "Önceki")
                    playPauseButton(isPlaying: media.isPlaying)
                    mediaButton("forward.fill", "NEXT", help: "Sonraki")
                    if !compact {
                        Divider().frame(height: 22).padding(.horizontal, 4)
                        mediaButton("speaker.wave.1.fill", "VOLUME_DOWN", help: "Sesi kıs")
                        mediaButton("speaker.wave.3.fill", "VOLUME_UP", help: "Sesi aç")
                    }
                }
            }
            .padding(compact ? 10 : 14)
        }
    }

    private func mediaButton(_ icon: String, _ action: String, help: String) -> some View {
        Button { viewModel.sendMediaCommand(action) } label: {
            Image(systemName: icon)
                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                .frame(width: compact ? 22 : 30, height: compact ? 22 : 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func playPauseButton(isPlaying: Bool) -> some View {
        let help = isPlaying ? "Duraklat" : "Oynat"
        return Button { viewModel.sendMediaCommand("PLAY_PAUSE") } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: compact ? 14 : 18, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: compact ? 30 : 42, height: compact ? 30 : 42)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassSurface(in: Circle(), tint: Color.synapseBlue.opacity(0.25), interactive: true)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Quick actions

struct QuickActionsRow: View {
    @ObservedObject var viewModel: SynapseViewModel
    var compact = false

    var body: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                action(viewModel.isFindingPhone ? "Durdur" : "Telefonu Bul",
                       icon: viewModel.isFindingPhone ? "speaker.slash.fill" : "speaker.wave.3.fill",
                       tint: viewModel.isFindingPhone ? .red : .orange) {
                    viewModel.toggleFindPhone()
                }
                action("Dosya Gönder", icon: "doc.badge.arrow.up", tint: .synapseBlue) {
                    viewModel.pickAndSendFile()
                }
                action("Linki Gönder", icon: "link", tint: .synapseCyan) {
                    viewModel.sendClipboardLinkToPhone()
                }
                .help("Panodaki linki telefonda aç")
            }
        }
    }

    private func action(_ title: String, icon: String, tint: Color, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 15 : 18, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 9 : 12)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassSurface(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
    }
}

struct TransferMessageBanner: View {
    @ObservedObject var viewModel: SynapseViewModel

    var body: some View {
        if let message = viewModel.transferMessage {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill").foregroundStyle(Color.synapseBlue)
                Text(message).font(.system(size: 12, weight: .medium)).lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .insetRow(cornerRadius: 10)
            .transition(.opacity)
        }
    }
}

/// Highlights its content while files are dragged over it and sends them to the phone.
struct FileDropTarget: ViewModifier {
    @ObservedObject var viewModel: SynapseViewModel
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            Label("Telefona göndermek için bırakın", systemImage: "iphone.and.arrow.forward")
                                .font(.headline).foregroundStyle(Color.accentColor)
                        )
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL, .url], isTargeted: $isTargeted) { providers in
                viewModel.connectionStatus == .connected && viewModel.handleFileDrop(providers)
            }
    }
}

extension View {
    func sendsDroppedFiles(to viewModel: SynapseViewModel) -> some View {
        modifier(FileDropTarget(viewModel: viewModel))
    }
}

// MARK: - Notification reply

struct NotificationReplyField: View {
    @ObservedObject var viewModel: SynapseViewModel
    let notificationKey: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let status = viewModel.replyStatus[notificationKey]
        HStack(spacing: 8) {
            TextField("Yanıt yaz…", text: $text)
                .textFieldStyle(.plain).font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .insetRow(cornerRadius: 10)
                .focused($focused)
                .onSubmit(send)
                .disabled(status == .sending)
            if status == .sending {
                ProgressView().controlSize(.small)
            } else {
                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                }
                .glassButtonStyle(prominent: true)
                .help("Gönder")
                .accessibilityLabel("Yanıtı gönder")
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        if status == .failed {
            Text("Yanıt gönderilemedi").font(.caption2).foregroundStyle(.red)
        }
    }

    private func send() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        viewModel.replyToNotification(key: notificationKey, text: text)
        text = ""
    }
}
