import SwiftUI
import UIKit

// MARK: - Brand

struct MaybeWordmark: View {
    var size: CGFloat = 30

    var body: some View {
        HStack(spacing: -0.5) {
            Text("ma")
            Text("y").offset(y: size * 0.055)
            Text("be")
        }
        .font(.maybeRounded(size, weight: .black))
        .tracking(-size * 0.045)
        .foregroundStyle(MaybePalette.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("maybe")
    }
}

/// The app mark: a black `m` sitting in a glassy keycap.
struct MaybeMark: View {
    var size: CGFloat = 42

    var body: some View {
        Text("m")
            .font(.system(size: size * 0.56, weight: .black, design: .rounded))
            .foregroundStyle(MaybePalette.ink)
            .offset(y: -size * 0.03)
            .frame(width: size, height: size)
            .background {
                KeycapSurface(
                    color: Color.white.opacity(0.72),
                    cornerRadius: size * 0.3,
                    depth: max(2, size * 0.07)
                )
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Structure

struct SectionHeader: View {
    let title: String
    var count: Int?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.maybeSectionTitle)
                .foregroundStyle(MaybePalette.ink)

            if let count {
                Text("\(count)")
                    .font(.maybeMeta)
                    .foregroundStyle(MaybePalette.inkSoft)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.maybeMeta)
                    .foregroundStyle(MaybePalette.ink)
            }
        }
    }
}

struct ScreenTitle<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.maybeScreenTitle)
                .foregroundStyle(MaybePalette.ink)
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension ScreenTitle where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

// MARK: - Tags

struct TagChip: View {
    let name: String
    var color: Color = Color.white.opacity(0.72)
    var selected = false
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 5) {
            Text(name)
                .font(.system(size: 13, weight: .bold, design: .rounded))
            if onRemove != nil {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .black))
            }
        }
        .foregroundStyle(MaybePalette.ink)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background {
            KeycapSurface(
                color: selected ? color : Color.white.opacity(0.55),
                cornerRadius: 12,
                depth: 2
            )
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct TagRow: View {
    let tags: [String]
    var accent: Color = MaybePalette.yellow

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    TagChip(name: tag, color: accent.opacity(0.8), selected: true)
                }
            }
            .padding(.vertical, 3)
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }
}

/// Add and remove tags without typing commas.
struct TagEditor: View {
    @Binding var tags: [String]
    var suggestions: [String] = []

    @State private var draft = ""

    private var available: [String] {
        suggestions
            .filter { suggestion in
                !tags.contains { $0.caseInsensitiveCompare(suggestion) == .orderedSame }
            }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !tags.isEmpty {
                FlowLayout(spacing: 8, rowSpacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            remove(tag)
                        } label: {
                            TagChip(name: tag, color: MaybePalette.green, selected: true, onRemove: { remove(tag) })
                        }
                        .buttonStyle(PressableStyle(scale: 0.94))
                        .accessibilityLabel("Remove tag \(tag)")
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Add a tag", text: $draft)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .submitLabel(.done)
                    .onSubmit { add(draft) }
                    .padding(14)
                    .maybePanel(cornerRadius: 16)
                    .accessibilityIdentifier("tag-field")

                Button {
                    add(draft)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(RoundKeycapButtonStyle(color: MaybePalette.green, size: 46))
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add tag")
            }

            if !available.isEmpty {
                FlowLayout(spacing: 8, rowSpacing: 8) {
                    ForEach(available, id: \.self) { tag in
                        Button {
                            add(tag)
                        } label: {
                            TagChip(name: tag)
                        }
                        .buttonStyle(PressableStyle(scale: 0.94))
                    }
                }
            }
        }
    }

    private func add(_ raw: String) {
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        guard !tag.isEmpty,
              !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return }
        tags.append(tag)
    }

    private func remove(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}

// MARK: - Media

/// Loads a locally stored image. Nothing here ever leaves the device.
struct LocalAttachmentImage: View {
    let attachment: MediaAttachment
    let accessibilityTitle: String
    var prefersOriginal = false
    var contentMode: ContentMode = .fill

    @State private var loadedImage: UIImage?
    private let mediaStore = LocalMediaStore()

    var body: some View {
        Group {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .accessibilityLabel(accessibilityTitle)
            } else {
                MaybePalette.ink.opacity(0.05)
                    .accessibilityLabel(accessibilityTitle)
            }
        }
        .task(id: imagePath) {
            let url = mediaStore.url(at: imagePath)
            let data = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: url, options: [.mappedIfSafe])
            }.value
            guard !Task.isCancelled, let data else { return }
            loadedImage = UIImage(data: data)
        }
    }

    private var imagePath: String {
        prefersOriginal ? attachment.localPath : (attachment.thumbnailPath ?? attachment.localPath)
    }
}

/// What a saved thing looks like before you open it.
/// A photo shows the photo. Everything else shows its own content — never invented artwork.
enum PreviewSize {
    /// Small enough that any text would be cut mid-word: show a mark instead.
    case thumbnail
    case compact
    case full
}

struct ItemPreview: View {
    let item: SavedItem
    var prefersOriginal = false
    var size: PreviewSize = .full
    var contentMode: ContentMode = .fill

    private var compact: Bool { size != .full }

    var body: some View {
        if let image = item.primaryImage {
            LocalAttachmentImage(
                attachment: image,
                accessibilityTitle: item.title,
                prefersOriginal: prefersOriginal,
                contentMode: contentMode
            )
        } else {
            contentCard
        }
    }

    private var tint: Color { Color(hex: item.accentHex) }

    @ViewBuilder
    private var contentCard: some View {
        if size == .thumbnail {
            ZStack {
                tint.opacity(0.34)
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(MaybePalette.ink.opacity(0.7))
            }
        } else {
            switch item.kind {
            case .note, .photo:
                textCard(
                    item.note.isEmpty ? item.title : item.note,
                    symbol: item.kind == .note ? "text.quote" : "photo"
                )
            case .link:
                linkCard
            case .file:
                fileCard
            }
        }
    }

    private func textCard(_ text: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 13 : 16, weight: .bold))
                .foregroundStyle(MaybePalette.ink.opacity(0.45))
            Text(text)
                .font(.system(size: compact ? 14 : 17, weight: .semibold, design: .rounded))
                .foregroundStyle(MaybePalette.ink)
                .lineLimit(compact ? 3 : 5)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(compact ? 12 : 16)
        .background(tint.opacity(0.34))
    }

    private var linkCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: compact ? 14 : 18, weight: .bold))
                .foregroundStyle(MaybePalette.ink)
            Spacer(minLength: 0)
            Text(item.hostName ?? item.title)
                .font(.system(size: compact ? 15 : 20, weight: .bold, design: .rounded))
                .foregroundStyle(MaybePalette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(compact ? 12 : 16)
        .background(tint.opacity(0.34))
    }

    private var fileCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            Text(item.fileExtension ?? "FILE")
                .font(.system(size: compact ? 20 : 30, weight: .black, design: .rounded))
                .foregroundStyle(MaybePalette.ink)
            Text(item.media.first?.originalFilename ?? item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MaybePalette.inkSoft)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(compact ? 12 : 16)
        .background(tint.opacity(0.34))
    }
}

// MARK: - Tiles

/// The saved thing itself is the card. No frame around a frame.
struct ItemTile: View {
    let item: SavedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Color.clear
                .aspectRatio(item.previewAspect, contentMode: .fit)
                .overlay { ItemPreview(item: item) }
                .clipShape(RoundedRectangle(cornerRadius: MaybeMetrics.tileRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: MaybeMetrics.tileRadius, style: .continuous)
                        .strokeBorder(MaybePalette.hairline, lineWidth: 1)
                }
                .overlay(alignment: .topTrailing) { badges }
                .shadow(color: MaybePalette.ink.opacity(0.10), radius: 1, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.maybeTileTitle)
                    .foregroundStyle(MaybePalette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !item.note.isEmpty, item.note != item.title {
                    Text(item.note)
                        .font(.system(size: 12.5))
                        .foregroundStyle(MaybePalette.inkSoft)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 5) {
            if item.isFavorite {
                badge {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(MaybePalette.coral)
                }
            }
            if item.imageCount > 1 {
                badge {
                    HStack(spacing: 3) {
                        Image(systemName: "square.on.square")
                            .font(.system(size: 9, weight: .black))
                        Text("\(item.imageCount)")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(MaybePalette.ink)
                }
            }
        }
        .padding(8)
    }

    private func badge<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(Color.white.opacity(0.55), in: Capsule())
            .glassEffect(.regular, in: Capsule())
    }
}

/// A compact row used in lists and pickers.
struct ItemRow: View {
    let item: SavedItem

    var body: some View {
        HStack(spacing: 12) {
            ItemPreview(item: item, size: .thumbnail)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(MaybePalette.hairline, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(MaybePalette.ink)
                    .lineLimit(1)
                Text(item.subtitleLine)
                    .font(.system(size: 12.5))
                    .foregroundStyle(MaybePalette.inkSoft)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Ideas

struct IdeaCard: View {
    let idea: Idea
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cover
                .frame(height: compact ? 118 : 168)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: MaybeMetrics.tileRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: MaybeMetrics.tileRadius, style: .continuous)
                        .strokeBorder(MaybePalette.hairline, lineWidth: 1)
                }
                .overlay(alignment: .bottomTrailing) {
                    if idea.items.count > 1 {
                        Text("+\(idea.items.count - 1)")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(MaybePalette.ink)
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(Color.white.opacity(0.55), in: Capsule())
                            .glassEffect(.regular, in: Capsule())
                            .padding(9)
                    }
                }
                .shadow(color: MaybePalette.ink.opacity(0.10), radius: 1, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(idea.title)
                    .font(.system(size: compact ? 15 : 17, weight: .bold, design: .rounded))
                    .foregroundStyle(MaybePalette.ink)
                    .lineLimit(1)
                Text(idea.items.isEmpty ? "Nothing linked yet" : "Inspired by \(idea.items.count)")
                    .font(.maybeMeta)
                    .foregroundStyle(MaybePalette.inkSoft)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: compact ? 210 : nil, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// One cover, filling the band. Collages of three squashed thumbnails made
    /// every idea look the same and cut their contents in half.
    @ViewBuilder
    private var cover: some View {
        if let item = idea.coverItem {
            ItemPreview(item: item)
        } else {
            ZStack {
                Color(hex: idea.accentHex).opacity(0.34)
                Image(systemName: "lightbulb")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(MaybePalette.ink.opacity(0.45))
            }
        }
    }
}

// MARK: - Masonry

/// Two-column waterfall. Tiles keep their own proportions, so nothing is cropped
/// to fit a grid cell.
struct MasonryGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let columns: Int
    let spacing: CGFloat
    let rowSpacing: CGFloat
    let ratio: (Item) -> CGFloat
    let content: (Item) -> Content

    init(
        items: [Item],
        columns: Int = 2,
        spacing: CGFloat = MaybeMetrics.gutter,
        rowSpacing: CGFloat = 22,
        ratio: @escaping (Item) -> CGFloat,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.columns = columns
        self.spacing = spacing
        self.rowSpacing = rowSpacing
        self.ratio = ratio
        self.content = content
    }

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(distributed.enumerated()), id: \.offset) { _, column in
                LazyVStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(column) { item in
                        content(item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private var distributed: [[Item]] {
        var buckets = Array(repeating: [Item](), count: max(1, columns))
        var heights = Array(repeating: CGFloat.zero, count: max(1, columns))
        for item in items {
            let shortest = heights.enumerated().min { $0.element < $1.element }?.offset ?? 0
            buckets[shortest].append(item)
            // Relative height: image box plus the caption underneath.
            heights[shortest] += 1 / max(ratio(item), 0.2) + 0.42
        }
        return buckets
    }
}

// MARK: - Flow layout

/// Wraps chips onto as many lines as they need instead of scrolling them
/// off the edge of the screen.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + rowSpacing
                widestRow = max(widestRow, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        widestRow = max(widestRow, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: min(widestRow, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Empty states

struct EmptyLibraryView: View {
    let symbol: String
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(MaybePalette.ink)
                .frame(width: 64, height: 60)
                .background { KeycapSurface(color: MaybePalette.yellow, cornerRadius: 20) }

            Text(title)
                .font(.maybeRounded(19, weight: .bold))
                .foregroundStyle(MaybePalette.ink)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(KeycapButtonStyle(color: MaybePalette.purple.opacity(0.9), minHeight: 48))
                    .frame(maxWidth: 240)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}
