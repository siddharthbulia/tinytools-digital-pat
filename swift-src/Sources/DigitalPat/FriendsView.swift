import SwiftUI

/// Onboarding until you've picked a name, then the Friends manager.
struct FriendsRootView: View {
    @ObservedObject var store = FriendStore.shared
    var body: some View {
        if store.hasOnboarded { FriendsView() } else { OnboardingView() }
    }
}

// MARK: - Onboarding (name + avatar)

struct OnboardingView: View {
    @State private var name = ""
    @State private var character = Characters.shared.currentId
    @State private var busy = false
    private var ids: [String] { Characters.shared.availableIds() }
    private var canStart: Bool { !busy && !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hi! I'm Pat 🐱").font(.title2).bold()
            Text("Pick your name and your little character. Then add a friend and your pixel selves will hang out on each other's desktops.")
                .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)

            Text("YOUR NAME").font(.caption2).foregroundColor(.secondary)
            TextField("e.g. GD", text: $name).textFieldStyle(.roundedBorder)

            Text("PICK YOUR CHARACTER").font(.caption2).foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ids, id: \.self) { id in AvatarChip(id: id, selected: id == character) { character = id } }
                }.padding(.vertical, 2)
            }.frame(height: 80)

            HStack {
                Spacer()
                Button(busy ? "…" : "Let's go 🎉") { start() }
                    .keyboardShortcut(.defaultAction).disabled(!canStart)
            }
        }
        .padding(20).frame(width: 380)
    }

    private func start() {
        busy = true
        let nm = name.trimmingCharacters(in: .whitespaces)
        Characters.shared.setCurrent(character)
        Task { await FriendStore.shared.start(name: nm, character: character); busy = false }
    }
}

struct AvatarChip: View {
    let id: String; let selected: Bool; let tap: () -> Void
    var body: some View {
        Button(action: tap) {
            VStack(spacing: 3) {
                if let img = Sprites.image(characterId: id, mood: "neutral") {
                    Image(nsImage: img).interpolation(.none).resizable().frame(width: 44, height: 44)
                } else { Image(systemName: "questionmark").frame(width: 44, height: 44) }
                Text(Characters.shared.displayName(id)).font(.system(size: 9)).lineLimit(1)
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        }.buttonStyle(.plain)
    }
}

// MARK: - Friends manager

struct FriendsView: View {
    @ObservedObject var store = FriendStore.shared
    @State private var inviteCode: String?
    @State private var addingCode = ""
    @State private var addStatus: String?
    @State private var refreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Your friends 🐾").font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(refreshing ? 360 : 0))
                        .animation(refreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: refreshing)
                }
                .buttonStyle(.plain).foregroundColor(.secondary).disabled(refreshing)
                .help("Refresh — reconnect and re-sync your friends")
                Text("\(store.friends.count)").font(.caption).foregroundColor(.secondary)
            }

            if store.friends.isEmpty {
                VStack(spacing: 6) {
                    Text("🫧").font(.system(size: 30))
                    Text("no friends yet!\ninvite someone below — you'll live on each other's desktops.")
                        .font(.system(size: 11, design: .rounded)).multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 10)
            } else {
                // A plain VStack sizes to its rows; only wrap in a FIXED-height scroller when the list
                // is long. (A bare ScrollView with only maxHeight collapses to ~0 in this content-sized
                // window — that was the "count says N but the list is empty" bug.)
                let rows = VStack(spacing: 6) { ForEach(store.friends) { f in FriendRow(friend: f) } }
                if store.friends.count <= 6 {
                    rows
                } else {
                    ScrollView { rows }.frame(height: 300)
                }
            }

            Divider()

            // Invite a friend
            VStack(alignment: .leading, spacing: 6) {
                Text("INVITE A FRIEND").font(.caption2).foregroundColor(.secondary)
                if let code = inviteCode {
                    HStack(spacing: 6) {
                        Text(code).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.1)))
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code, forType: .string)
                        }.font(.system(size: 11))
                    }
                    Text("Send this code to your friend; they paste it under “Add a friend.” One-time use.")
                        .font(.system(size: 9)).foregroundColor(.secondary)
                } else {
                    Button("Create an invite code") {
                        Task {
                            if let code = await FriendStore.shared.createInvite() { inviteCode = code }
                            else { addStatus = "couldn't create an invite — check your connection" }
                        }
                    }.font(.system(size: 12, weight: .semibold))
                }
            }

            // Add by code
            VStack(alignment: .leading, spacing: 6) {
                Text("ADD A FRIEND").font(.caption2).foregroundColor(.secondary)
                HStack(spacing: 6) {
                    TextField("paste invite code", text: $addingCode)
                        .textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(addingCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let s = addStatus { Text(s).font(.system(size: 10)).foregroundColor(.secondary) }
            }
        }
        .padding(16).frame(width: 320)
    }

    private func add() {
        let code = addingCode
        addStatus = "adding…"
        Task {
            let ok = await FriendStore.shared.acceptInvite(code)
            addStatus = ok ? "added! 🎉" : "couldn't add — check the code"
            if ok { addingCode = "" }
        }
    }

    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            await FriendStore.shared.refreshNow()
            try? await Task.sleep(nanoseconds: 400_000_000)   // let the spinner read as a deliberate beat
            refreshing = false
        }
    }
}

struct FriendRow: View {
    let friend: Friend
    var body: some View {
        HStack(spacing: 9) {
            if let img = Sprites.image(characterId: friend.character, mood: friend.online ? friend.mood : "idle") {
                Image(nsImage: img).interpolation(.none).resizable().frame(width: 38, height: 38)
                    .opacity(friend.online ? 1 : 0.55)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(friend.name).font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(friend.online ? (Mood(rawValue: friend.mood) ?? .neutral).label.lowercased() : "away")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Circle().fill(friend.online ? Color.green : Color.secondary.opacity(0.35)).frame(width: 7, height: 7)
            Menu {
                Button("Remove friend") { Task { await FriendStore.shared.removeFriend(friend.uid) } }
            } label: { Image(systemName: "ellipsis").font(.system(size: 12)) }
                .menuStyle(.borderlessButton).frame(width: 22)
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }
}
