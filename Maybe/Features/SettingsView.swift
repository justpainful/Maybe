import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [SavedItem]
    @Query private var ideas: [Idea]

    @State private var exportDocument: MaybeArchiveDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                CreamCanvas()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        privacyHero
                        counts
                        backupSection
                        promises
                    }
                    .padding(.horizontal, MaybeMetrics.pageInset)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .maybeLibrary,
                defaultFilename: "Maybe Library"
            ) { result in
                switch result {
                case .success: statusMessage = "Your library was exported."
                case .failure(let error): statusMessage = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.maybeLibrary],
                allowsMultipleSelection: false,
                onCompletion: importLibrary
            )
            .alert("Maybe", isPresented: statusBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(statusMessage ?? "Done")
            }
        }
    }

    private var privacyHero: some View {
        VStack(spacing: 12) {
            MaybeMark(size: 72)
            Text("Everything stays\non this device.")
                .font(.maybeRounded(25, weight: .black))
                .foregroundStyle(MaybePalette.ink)
                .multilineTextAlignment(.center)
            Text("No account. No cloud. No tracking.")
                .font(.system(size: 14))
                .foregroundStyle(MaybePalette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(MaybePalette.green.opacity(0.3), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(MaybePalette.hairline, lineWidth: 1)
        }
    }

    private var counts: some View {
        HStack(spacing: 12) {
            countCard(value: items.count, label: "Things", color: MaybePalette.blue)
            countCard(value: ideas.count, label: "Ideas", color: MaybePalette.yellow)
        }
    }

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Backup")

            Button(action: exportLibrary) {
                Text("Export my library")
            }
            .buttonStyle(KeycapButtonStyle(color: MaybePalette.purple, cornerRadius: 18))

            Button {
                isImporting = true
            } label: {
                Text("Import a library")
            }
            .buttonStyle(KeycapButtonStyle(color: Color.white.opacity(0.7), cornerRadius: 18))

            Text("One file with every photo, note and idea. Move it between your own devices by hand.")
                .font(.system(size: 13))
                .foregroundStyle(MaybePalette.inkSoft)
        }
    }

    private var promises: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Private by design")
            promiseRow("No login")
            promiseRow("No analytics")
            promiseRow("No remote database")
            promiseRow("Nothing is uploaded, ever")
        }
    }

    private func countCard(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.maybeRounded(28, weight: .black))
                .monospacedDigit()
                .foregroundStyle(MaybePalette.ink)
            Text(label)
                .font(.maybeMeta)
                .foregroundStyle(MaybePalette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.34), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(MaybePalette.hairline, lineWidth: 1)
        }
    }

    private func promiseRow(_ title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(MaybePalette.ink)
                .frame(width: 30, height: 30)
                .background { KeycapSurface(color: MaybePalette.green, cornerRadius: 10, depth: 2) }
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(MaybePalette.ink)
            Spacer(minLength: 0)
        }
        .padding(10)
        .maybePanel(cornerRadius: 18)
    }

    private var statusBinding: Binding<Bool> {
        Binding(get: { statusMessage != nil }, set: { if !$0 { statusMessage = nil } })
    }

    private func exportLibrary() {
        do {
            exportDocument = MaybeArchiveDocument(
                wrapper: try LibraryArchiveService.exportPackage(items: items, ideas: ideas)
            )
            isExporting = true
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func importLibrary(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let wrapper = try FileWrapper(url: url, options: .immediate)
            let count = try LibraryArchiveService.importPackage(wrapper: wrapper, into: modelContext)
            statusMessage = "Imported \(count) new things."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
