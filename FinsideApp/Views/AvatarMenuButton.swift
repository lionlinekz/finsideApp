import SwiftUI
import UIKit

struct AvatarMenuButton: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Menu {
            if let user = appState.user {
                Section {
                    Text("\(user.firstName) \(user.lastName)")
                    Text(user.email)
                        .foregroundStyle(.secondary)
                }

                if !user.companyLine.isEmpty || !user.jobLine.isEmpty {
                    Section {
                        if !user.companyLine.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Компания")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(user.companyLine)
                                    .font(.subheadline)
                            }
                        }
                        if !user.jobLine.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Должность")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(user.jobLine)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    appState.logout()
                } label: {
                    Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } label: {
            avatarImage
        }
    }

    private var avatarImage: some View {
        Group {
            if let user = appState.user {
                avatarFilled(for: user)
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func avatarFilled(for user: UserInfo) -> some View {
        UserAvatarBadge(user: user, colorScheme: colorScheme)
    }
}

// MARK: - Remote avatar (Bearer + те же cookie-политики, что у API — не только AsyncImage без заголовков)

private enum AvatarImageLoader {
    static func load(url: URL) async -> UIImage? {
        func fetch(authorized: Bool) async -> UIImage? {
            var request = URLRequest(url: url)
            request.httpShouldHandleCookies = true
            if authorized,
               let token = KeychainService.read(key: .accessToken)?
                   .trimmingCharacters(in: .whitespacesAndNewlines),
               !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { return nil }
                guard (200...299).contains(http.statusCode) else { return nil }
                guard let img = UIImage(data: data), img.size.width > 0 else { return nil }
                return img
            } catch {
                return nil
            }
        }
        if let img = await fetch(authorized: true) { return img }
        return await fetch(authorized: false)
    }
}

private struct UserAvatarBadge: View {
    let user: UserInfo
    let colorScheme: ColorScheme

    @State private var loaded: UIImage?

    private var initialsText: String {
        let first = user.firstName.prefix(1).uppercased()
        let last = user.lastName.prefix(1).uppercased()
        if first.isEmpty && last.isEmpty { return "?" }
        return "\(first)\(last)"
    }

    private var remoteURL: URL? {
        let s = user.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .overlay {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

            Text(initialsText)
                .font(.caption.bold())
                .foregroundStyle(.white)

            if let loaded {
                Image(uiImage: loaded)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(
                    Color.white.opacity(colorScheme == .dark ? 0.20 : 0.35),
                    lineWidth: 0.5
                )
        }
        .shadow(
            color: Color.accentColor.opacity(0.3),
            radius: 4, y: 2
        )
        .task(id: user.avatarURL ?? "") {
            guard let remoteURL else {
                loaded = nil
                return
            }
            let img = await AvatarImageLoader.load(url: remoteURL)
            await MainActor.run {
                loaded = img
            }
        }
    }
}

private extension UserInfo {
    var companyLine: String {
        (companyName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var jobLine: String {
        (jobTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
