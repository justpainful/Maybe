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
                        librarySection
                        factsSection

                        Text("Maybe is a quiet place for the things that catch you — and the ideas they become.")
                            .font(.footnote)
                            .foregroundStyle(MaybePalette.ink.opacity(0.52))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                    .padding(20)
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
        VStack(spacing: 15) {
            MaybeMark(size: 82)
            Text("Everything stays\non this device.")
                .font(.maybeRounded(28, weight: .black))
                .multilineTextAlignment(.center)
            Text("No account. No cloud. No tracking.")
                .font(.subheadline)
                .foregroundStyle(MaybePalette.ink.opacity(0.58))
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .background(MaybePalette.green.opacity(0.35), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .maybeGlass(cornerRadius: 30, tint: MaybePalette.green.opacity(0.16))
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Your library")
                .font(.maybeRounded(22, weight: .bold))

            HStack(spacing: 12) {
                statCard(value: "\(items.count)", label: "Things", color: MaybePalette.blue)
                statCard(value: "\(ideas.count)", label: "Ideas", color: MaybePalette.yellow)
            }

            Button(action: exportLibrary) {
                Label("Export Maybe", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: 20))
            .tint(MaybePalette.purple)
            .foregroundStyle(MaybePalette.ink)

            Button {
                isImporting = true
            } label: {
                Label("Import Maybe", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.roundedRectangle(radius: 20))
            .tint(MaybePalette.glassWhite)
            .foregroundStyle(MaybePalette.ink)
        }
    }

    private var factsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Private by design")
                .font(.maybeRounded(22, weight: .bold))
            privacyRow("No login", symbol: "person.crop.circle.badge.xmark", color: MaybePalette.coral)
            privacyRow("No analytics SDK", symbol: "chart.bar.xaxis", color: MaybePalette.blue)
            privacyRow("No remote database", symbol: "externaldrive.badge.xmark", color: MaybePalette.green)
            privacyRow("Manual backup whenever you want", symbol: "shippingbox.fill", color: MaybePalette.yellow)
        }
    }

    private func statCard(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.maybeRounded(30, weight: .black))
            Text(label)
                .font(.caption)
                .foregroundStyle(MaybePalette.ink.opacity(0.58))
        }
        .frame(maxWidth: .infinity)
        .padding(17)
        .background(color.opacity(0.42), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .maybeGlass(cornerRadius: 22, tint: color.opacity(0.16))
    }

    private func privacyRow(_ title: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 44, height: 42)
                .background(color.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(title)
                .font(.system(.body, design: .rounded, weight: .semibold))
            Spacer()
            Image(systemName: "checkmark")
                .font(.caption.bold())
        }
        .padding(10)
        .background(Color.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .maybeGlass(cornerRadius: 19)
    }

    private var statusBinding: Binding<Bool> {
        Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )
    }

    private func exportLibrary() {
        do {
            exportDocument = MaybeArchiveDocument(wrapper: try LibraryArchiveService.exportPackage(items: items, ideas: ideas))
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
