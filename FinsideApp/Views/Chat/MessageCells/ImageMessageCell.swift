import SwiftUI

/// Сообщение «как iMessage с фото»: один или несколько image-attachments + опциональная подпись.
struct ImageMessageCell: View {
    let message: ChatMessage
    @Environment(\.colorScheme) private var colorScheme
    @State private var fullScreenAttachment: ChatAttachment?

    private var images: [ChatAttachment] { message.imageAttachments }

    private var isOwn: Bool {
        message.senderId != nil && !message.isSystem
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isOwn { Spacer(minLength: 56) }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 5) {
                if !message.senderName.isEmpty {
                    Text(message.senderName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                imagesContainer

                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(isOwn ? Color.white : Color.primary)
                        .multilineTextAlignment(isOwn ? .trailing : .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(isOwn ? Color.accentColor : incomingFill)
                        }
                }

                Text(message.formattedTime)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 280, alignment: isOwn ? .trailing : .leading)

            if !isOwn { Spacer(minLength: 56) }
        }
        .frame(maxWidth: .infinity)
        .fullScreenCover(item: $fullScreenAttachment) { att in
            ImageAttachmentFullScreen(attachment: att) {
                fullScreenAttachment = nil
            }
        }
    }

    @ViewBuilder
    private var imagesContainer: some View {
        if images.count == 1, let only = images.first {
            singleImage(only)
        } else if images.count == 2 {
            HStack(spacing: 3) {
                imageThumbnail(images[0], aspect: 1.0)
                imageThumbnail(images[1], aspect: 1.0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)],
                spacing: 3
            ) {
                ForEach(images.prefix(4)) { att in
                    imageThumbnail(att, aspect: 1.0)
                        .overlay(alignment: .bottomTrailing) {
                            if att.id == images[3].id && images.count > 4 {
                                Text("+\(images.count - 4)")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(.black.opacity(0.35))
                            }
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func singleImage(_ att: ChatAttachment) -> some View {
        AsyncImage(url: att.fileURL) { phase in
            switch phase {
            case .empty:
                placeholder(aspect: att.aspectRatio)
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 260)
                    .frame(
                        height: min(max(260 / max(att.aspectRatio, 0.6), 160), 360)
                    )
                    .clipped()
            case .failure:
                placeholder(aspect: att.aspectRatio)
                    .overlay {
                        Image(systemName: "photo.badge.exclamationmark")
                            .foregroundStyle(.secondary)
                    }
            @unknown default:
                placeholder(aspect: att.aspectRatio)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { fullScreenAttachment = att }
        .accessibilityAddTraits(.isImage)
    }

    private func imageThumbnail(_ att: ChatAttachment, aspect: CGFloat) -> some View {
        AsyncImage(url: att.fileURL) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill()
            case .empty, .failure:
                placeholder(aspect: aspect)
            @unknown default:
                placeholder(aspect: aspect)
            }
        }
        .aspectRatio(aspect, contentMode: .fill)
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { fullScreenAttachment = att }
    }

    private func placeholder(aspect: CGFloat) -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.18))
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                ProgressView()
            }
    }

    private var incomingFill: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemFill)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.secondary.opacity(0.14)
        #endif
    }
}

// MARK: - Full screen viewer

private struct ImageAttachmentFullScreen: View {
    let attachment: ChatAttachment
    let onClose: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AsyncImage(url: attachment.fileURL) { phase in
                switch phase {
                case .empty:
                    ProgressView().tint(.white)
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(1, lastScale * value)
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale < 1.05 {
                                        withAnimation { scale = 1; lastScale = 1 }
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation { scale = scale > 1.1 ? 1 : 2.5; lastScale = scale }
                        }
                case .failure:
                    Image(systemName: "photo")
                        .font(.system(size: 72))
                        .foregroundStyle(.white.opacity(0.4))
                @unknown default:
                    EmptyView()
                }
            }
            .padding()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}
