import SwiftUI

struct ChatsView: View {
    var body: some View {
        ChatListView()
    }
}

#Preview {
    ChatsView()
        .environment(ChatService())
}
