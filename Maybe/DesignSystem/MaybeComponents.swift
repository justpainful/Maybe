import SwiftUI
import UIKit

struct MaybeWordmark: View {
    var size: CGFloat = 36

    var body: some View {
        HStack(spacing: -1) {
            Text("ma")
            Text("y").offset(y: 1.5)
            Text("be")
        }
        .font(.maybeRounded(size, weight: .black))
        .tracking(-1.45)
        .foregroundStyle(MaybePalette.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("maybe")
    }
}

struct MaybeMark: View {
    var size: CGFloat = 48

    var body: some View {
        let gap = size * 0.055
        let innerSize = size * 0.58
        let tile = (innerSize - gap) / 2
        let radius = size * 0.24

        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.white.opacity(0.32))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.92), lineWidth: max(1, size * 0.025))
                        .padding(1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(MaybePalette.ink.opacity(0.09), lineWidth: 0.75)
                }

            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    markTile(MaybePalette.coral, size: tile)
                    markTile(MaybePalette.yellow, size: tile)
                        .overlay {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: size * 0.18, weight: .black, design: .rounded))
                                .foregroundStyle(MaybePalette.ink)
                        }
                }
                HStack(alignment: .top, spacing: gap) {
                    markTile(MaybePalette.blue, size: tile)
                    markTile(MaybePalette.green, size: tile * 0.72)
                        .frame(width: tile, height: tile, alignment: .topLeading)
                }
            }
            .frame(width: innerSize, height: innerSize)
        }
        .frame(width: size, height: size)
        .shadow(color: MaybePalette.ink.opacity(0.12), radius: 2, y: 3)
        .accessibilityHidden(true)
    }

    private func markTile(_ color: Color, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .stroke(Color.white.opacity(0.84), lineWidth: 0.9)
                    .padding(1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .stroke(MaybePalette.ink.opacity(0.12), lineWidth: 0.65)
            }
            .shadow(color: MaybePalette.ink.opacity(0.18), radius: 0.5, y: 1.5)
    }
}

struct MaybeHeader: View {
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            MaybeMark(size: 48)
            MaybeWordmark(size: 32)
            Spacer()
            if let trailingAction {
                Button(action: trailingAction) {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(RoundKeycapButtonStyle(color: MaybePalette.glassWhite, size: 44))
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("settings-button")
            }
        }
    }
}

struct MaybeSectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.maybeRounded(24, weight: .bold))
                    .foregroundStyle(MaybePalette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(MaybePalette.ink.opacity(0.56))
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(MaybePalette.ink)
            }
        }
    }
}

struct TagChip: View {
    let name: String
    var color: Color = MaybePalette.glassWhite
    var selected = false

    var body: some View {
        Text(name)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(MaybePalette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background((selected ? color : color.opacity(0.62)), in: Capsule())
            .overlay(alignment: .top) {
                Capsule()
                    .stroke(Color.white.opacity(0.76), lineWidth: 1)
                    .padding(1)
            }
            .overlay(Capsule().stroke(MaybePalette.ink.opacity(selected ? 0.22 : 0.12), lineWidth: 1))
            .shadow(color: MaybePalette.ink.opacity(0.12), radius: 0.5, y: 2)
    }
}

struct FlowTags: View {
    let tags: [String]
    var accent: Color = MaybePalette.purple

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(tags, id: \.self) { tag in
                    TagChip(name: tag, color: accent.opacity(0.55))
                }
            }
        }
        .scrollEdgeEffectHidden(true, for: .all)
    }
}

struct TagGrid: View {
    let tags: [String]
    var accent: Color = MaybePalette.green

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                TagChip(name: tag, color: accent.opacity(0.7))
            }
        }
    }
}

struct SavedCard: View {
    let item: SavedItem
    var width: CGFloat? = 166

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            InspirationThumbnail(item: item)
                .frame(height: width.map { max(130, $0 * 0.82) } ?? 142)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 6) {
                    Text(item.title)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(MaybePalette.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    if item.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(MaybePalette.coral)
                    }
                }

                Text(item.note.isEmpty ? item.kind.title : item.note)
                    .font(.caption)
                    .foregroundStyle(MaybePalette.ink.opacity(0.56))
                    .lineLimit(2)
            }
            .padding(.horizontal, 3)
        }
        .padding(8)
        .frame(width: width, alignment: .leading)
        .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.9), lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(MaybePalette.ink.opacity(0.06), lineWidth: 0.75))
        .shadow(color: MaybePalette.ink.opacity(0.13), radius: 2, y: 4)
    }
}

struct InspirationThumbnail: View {
    let item: SavedItem
    var prefersOriginal = false
    private let mediaStore = LocalMediaStore()
    @State private var loadedImage: UIImage?

    var body: some View {
        if let attachment = item.media.first,
           attachment.type == .image,
           let image = loadedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .accessibilityLabel(item.title)
        } else {
            generatedArtwork
                .accessibilityLabel("Preview for \(item.title)")
        }
        .task(id: imagePath) {
            loadedImage = nil
            guard let imagePath else { return }
            let url = mediaStore.url(at: imagePath)
            let data = await Task.detached(priority: .utility) {
                try? Data(contentsOf: url, options: [.mappedIfSafe])
            }.value
            guard !Task.isCancelled, let data else { return }
            loadedImage = UIImage(data: data)
        }
    }

    private var imagePath: String? {
        guard let attachment = item.media.first, attachment.type == .image else { return nil }
        return prefersOriginal ? attachment.localPath : (attachment.thumbnailPath ?? attachment.localPath)
    }

    @ViewBuilder
    private var generatedArtwork: some View {
        switch item.visualSeed % 5 {
        case 0:
            ZStack {
                LinearGradient(
                    colors: [MaybePalette.cream, Color(hex: "DDEBFF")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        glassControl(symbol: "sparkles", color: MaybePalette.purple)
                        glassControl(symbol: "slider.horizontal.3", color: MaybePalette.coral)
                    }
                    HStack(spacing: 12) {
                        glassControl(symbol: "heart.fill", color: MaybePalette.blue)
                        glassControl(symbol: "plus", color: MaybePalette.yellow)
                    }
                }
                .rotationEffect(.degrees(-5))
            }
        case 1:
            ZStack {
                MaybePalette.green.opacity(0.62)
                HStack(alignment: .bottom, spacing: 7) {
                    keycap("M", MaybePalette.coral, height: 62)
                    keycap("A", MaybePalette.blue, height: 76)
                    keycap("Y", MaybePalette.yellow, height: 94)
                }
                .rotationEffect(.degrees(3))
            }
        case 2:
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [MaybePalette.coral, MaybePalette.yellow],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text("Aa")
                    .font(.maybeRounded(78, weight: .black))
                    .tracking(-7)
                    .foregroundStyle(MaybePalette.ink)
                    .padding(18)
            }
        case 3:
            ZStack {
                MaybePalette.green
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.38))
                    .frame(width: 116, height: 96)
                    .overlay {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .foregroundStyle(MaybePalette.ink)
                    }
                    .maybeGlass(cornerRadius: 24)
                    .rotationEffect(.degrees(-6))
            }
        default:
            ZStack {
                MaybePalette.cream
                HStack(spacing: -8) {
                    ForEach(Array(MaybePalette.accents.enumerated()), id: \.offset) { index, color in
                        Circle()
                            .fill(color)
                            .frame(width: 50, height: 50)
                            .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 2))
                            .offset(y: index.isMultiple(of: 2) ? -12 : 12)
                    }
                }
            }
        }
    }

    private func glassControl(symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(MaybePalette.ink)
            .frame(width: 54, height: 48)
            .background(color.opacity(0.72), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.white.opacity(0.75), lineWidth: 1))
            .shadow(color: MaybePalette.ink.opacity(0.15), radius: 2, y: 3)
    }

    private func keycap(_ letter: String, _ color: Color, height: CGFloat) -> some View {
        Text(letter)
            .font(.maybeRounded(24, weight: .black))
            .foregroundStyle(MaybePalette.ink)
            .frame(width: 48, height: height, alignment: .top)
            .padding(.top, 12)
            .background(color, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(MaybePalette.ink.opacity(0.6), lineWidth: 1.2))
            .shadow(color: MaybePalette.ink.opacity(0.35), radius: 0, y: 5)
    }
}

struct IdeaCard: View {
    let idea: Idea
    var compact = false

    private var previewItems: [SavedItem] {
        guard let coverID = idea.coverItemID,
              let cover = idea.items.first(where: { $0.id == coverID }) else {
            return Array(idea.items.prefix(3))
        }
        return [cover] + Array(idea.items.filter { $0.id != coverID }.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .fill(Color(hex: idea.accentHex).opacity(0.3))

                HStack(spacing: -28) {
                    ForEach(Array(previewItems.enumerated()), id: \.element.id) { index, item in
                        InspirationThumbnail(item: item)
                            .frame(width: compact ? 76 : 94, height: compact ? 88 : 108)
                            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.white, lineWidth: 2))
                            .rotationEffect(.degrees(Double(index - 1) * 6))
                            .shadow(color: MaybePalette.ink.opacity(0.16), radius: 4, y: 4)
                    }
                }
            }
            .frame(height: compact ? 128 : 156)

            VStack(alignment: .leading, spacing: 4) {
                Text(idea.title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(MaybePalette.ink)
                Text("Inspired by \(idea.items.count) things")
                    .font(.caption)
                    .foregroundStyle(MaybePalette.ink.opacity(0.56))
            }
        }
        .padding(10)
        .frame(width: compact ? 212 : nil, alignment: .leading)
        .frame(maxWidth: compact ? 212 : .infinity, alignment: .leading)
        .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 29, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 29, style: .continuous).stroke(Color.white.opacity(0.8), lineWidth: 1))
        .shadow(color: MaybePalette.ink.opacity(0.13), radius: 2, y: 4)
    }
}

struct EmptyLibraryView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(MaybePalette.ink)
                .frame(width: 78, height: 72)
                .background(MaybePalette.yellow.opacity(0.72), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .maybeGlass(cornerRadius: 24, tint: MaybePalette.yellow.opacity(0.28))
            Text(title)
                .font(.maybeRounded(22, weight: .bold))
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(MaybePalette.ink.opacity(0.58))
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }
}
