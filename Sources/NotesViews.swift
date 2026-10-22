import SwiftUI
import AVKit

// MARK: - Note preview (Instagram for iOS)
//
// Tapping a note opens it large: the thought bubble over the author's photo, the song with its cover
// (playing straight away, as in the app), when it was shared, and a field to reply by message.

struct NoteSheet: View {
    let note: IGNote
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var reply = ""
    @State private var state: SendState = .idle
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var confirmDelete = false

    private enum SendState: Equatable { case idle, sending, sent, failed }
    private var isOwn: Bool { note.user.id == store.viewerID }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.quaternary))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            VStack(spacing: 10) {
                if !note.text.isEmpty {
                    Text(note.text)
                        .font(.system(size: 17, weight: .medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(light: 0xF2F2F2, dark: 0x2C2C2E)))
                        .frame(maxWidth: 300)
                }
                AvatarView(url: note.user.avatarURL, size: 96)
                VStack(spacing: 2) {
                    Text(isOwn ? "Notun" : note.user.username)
                        .font(.system(size: 15, weight: .semibold))
                    Text(note.createdAt.igAge)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
            }

            if let title = note.musicTitle {
                musicRow(title: title)
            }

            Spacer(minLength: 0)

            if isOwn {
                HStack(spacing: 8) {
                    Button("Yeni not bırak") {
                        dismiss()
                        store.isComposingNote = true
                    }
                    .buttonStyle(IGButtonStyle(kind: .primary))
                    Button("Notu sil", role: .destructive) { confirmDelete = true }
                        .buttonStyle(IGButtonStyle())
                }
            } else {
                replyField
                Button("Profili gör") {
                    dismiss()
                    store.openProfile(of: note.user)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.igBlue)
            }
        }
        .padding(20)
        .frame(width: 380, height: 520)
        .onAppear { if note.musicPreviewURL != nil { togglePlayback() } }
        .onDisappear { player?.pause() }
        .confirmationDialog("Notun silinsin mi?", isPresented: $confirmDelete) {
            Button("Sil", role: .destructive) {
                Task {
                    if await store.deleteOwnNote() { dismiss() }
                }
            }
        }
    }

    private func musicRow(title: String) -> some View {
        HStack(spacing: 10) {
            RemoteImage(url: note.musicCoverURL, maxPixelSize: 120)
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 6, style: .continuous))
                .overlay {
                    if note.musicCoverURL == nil {
                        Image(systemName: "music.note").foregroundStyle(.secondary)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                if let artist = note.musicArtist {
                    Text(artist)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(note.musicPreviewURL == nil)
            .help(note.musicPreviewURL == nil ? "Şarkı önizlemesi yok" : "Çal / Duraklat")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.5)))
    }

    private var replyField: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                TextField("\(note.user.username) adlı kişiye yanıt ver…", text: $reply)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .onSubmit(sendReply)
                    .disabled(state == .sending)
                if state == .sending {
                    ProgressView().controlSize(.small)
                } else if !reply.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: sendReply) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.messagesBlue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 5)
            .frame(height: 36)
            .glassEffect(.regular, in: .capsule)

            switch state {
            case .sent:
                Label("Yanıt mesaj olarak gönderildi", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(.green)
            case .failed:
                Label("Yanıt gönderilemedi", systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(.red)
            default:
                Text("Yanıtın \(note.user.username) adlı kişiye mesaj olarak gider.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        }
    }

    private func sendReply() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, state != .sending else { return }
        state = .sending
        Task {
            let ok = await store.replyToNote(note, text: text)
            withAnimation {
                state = ok ? .sent : .failed
                if ok { reply = "" }
            }
        }
    }

    private func togglePlayback() {
        guard let url = note.musicPreviewURL else { return }
        if player == nil { player = AVPlayer(url: url) }
        isPlaying.toggle()
        if isPlaying { player?.play() } else { player?.pause() }
    }
}

// MARK: - New note

struct NoteComposerSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var closeFriends = false
    @State private var isSharing = false
    @State private var failed = false
    @FocusState private var focused: Bool

    private let limit = 60

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button("Vazgeç") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("Yeni not").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Paylaş", action: share)
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isSharing)
                    .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.igBlue)

            VStack(spacing: 10) {
                TextField("Ne düşünüyorsun?", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(1...3)
                    .focused($focused)
                    .onChange(of: text) { _, value in
                        if value.count > limit { text = String(value.prefix(limit)) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(light: 0xF2F2F2, dark: 0x2C2C2E)))
                    .frame(maxWidth: 300)
                AvatarView(url: store.viewer?.avatarURL, size: 84)
                Text("\(text.count)/\(limit)")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Picker("Paylaşılan kişiler", selection: $closeFriends) {
                Text("Karşılıklı takipleştiklerin").tag(false)
                Text("Yakın Arkadaşlar").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("Notlar 24 saat boyunca gelen kutusunun üstünde görünür.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            if failed {
                Label("Not paylaşılamadı", systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 380, height: 420)
        .onAppear { focused = true }
    }

    private func share() {
        isSharing = true
        failed = false
        Task {
            let ok = await store.createNote(text: text, closeFriends: closeFriends)
            isSharing = false
            if ok { dismiss() } else { failed = true }
        }
    }
}
