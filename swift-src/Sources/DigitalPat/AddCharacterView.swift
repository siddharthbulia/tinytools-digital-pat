import SwiftUI
import UniformTypeIdentifiers

/// "Add a character" flow: pick a photo → generate a cute pixel companion (base + all
/// moods) via the Digital Pat backend, save it, and switch to it. No API key needed.
struct AddCharacterView: View {
    @StateObject private var gen = CharacterGenerator()
    @State private var name = ""
    @State private var photo: NSImage?

    var onDone: (String) -> Void
    var onClose: () -> Void

    private var canGenerate: Bool {
        !gen.busy && photo != nil
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a character 🐱").font(.title2).bold()
            Text("Turn any photo into a cute pixel companion. Just pick a photo — we'll draw all the poses for you, and the finished sprites stay on your Mac.")
                .font(.callout).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12))
                        .frame(width: 90, height: 90)
                    if let photo {
                        Image(nsImage: photo).resizable().scaledToFill()
                            .frame(width: 90, height: 90).clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "photo.badge.plus").font(.system(size: 26)).foregroundColor(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Button("Choose photo…") { pickPhoto() }
                    Text("A clear, front-facing photo works best.").font(.caption).foregroundColor(.secondary)
                }
            }

            TextField("Name (e.g. GD, Mom, Me)", text: $name).textFieldStyle(.roundedBorder)

            if gen.busy {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text(gen.progress).font(.callout).foregroundColor(.secondary)
                }
            }
            if let e = gen.error {
                Text(e).font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { onClose() }
                Spacer()
                Button(gen.busy ? "Generating…" : "Generate") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canGenerate)
            }
            Text("Generating all the poses takes a few minutes.")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 390)
    }

    private func pickPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) {
            photo = img
        }
    }

    private func start() {
        guard let photo else { return }
        let nm = name.trimmingCharacters(in: .whitespaces)
        Task {
            if let id = await gen.generate(name: nm, photo: photo) {
                onDone(id)
            }
        }
    }
}
