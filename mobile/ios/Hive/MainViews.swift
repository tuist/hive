import SwiftUI

struct LaunchView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                HiveMark()
                ProgressView()
                    .controlSize(.small)
            }
        }
        .accessibilityIdentifier("launch-screen")
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            ForageListView()
                .tabItem { Label("Forage", systemImage: "tray.full") }
            SpecListView()
                .tabItem { Label("Specs", systemImage: "doc.text") }
            DropListView()
                .tabItem { Label("Drops", systemImage: "shippingbox.fill") }
            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .tint(.indigo)
        .accessibilityIdentifier("main-navigation")
    }
}

struct ForageListView: View {
    @EnvironmentObject private var app: AppModel
    @State private var items: [ForageItem] = []
    @State private var query = ""
    @State private var errorMessage: String?
    @State private var isLoading = true

    private var visibleItems: [ForageItem] {
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.body?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView("Loading Forage…")
                } else if let errorMessage, items.isEmpty {
                    ContentUnavailableView(
                        "Forage could not load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if visibleItems.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(visibleItems) { item in
                        NavigationLink(value: item) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title)
                                    .font(.headline)
                                HStack(spacing: 8) {
                                    Text(readable(item.type))
                                    Text("•")
                                    Text(readable(item.status))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .navigationDestination(for: ForageItem.self) { item in
                        ForageDetailView(item: item)
                    }
                }
            }
            .navigationTitle("Forage")
            .searchable(text: $query, prompt: "Search Forage")
            .refreshable { await reload() }
            .task { await reload() }
        }
    }

    private func reload() async {
        guard items.isEmpty || !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await app.loadForage()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ForageDetailView: View {
    let item: ForageItem

    var body: some View {
        List {
            Section {
                LabeledContent("Status", value: readable(item.status))
                LabeledContent("Type", value: readable(item.type))
                if let source = item.sourceLabel {
                    LabeledContent("Source", value: source)
                }
            }

            if let body = item.body, !body.isEmpty {
                Section("Details") {
                    Text(body)
                        .textSelection(.enabled)
                }
            }

            if !item.domains.isEmpty {
                Section("Domains") {
                    ForEach(item.domains) { domain in
                        Label(domain.name, systemImage: "square.stack.3d.up")
                    }
                }
            }

            if let address = item.externalURL, let url = URL(string: address) {
                Section {
                    Link(destination: url) {
                        Label("Open source", systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SpecListView: View {
    @EnvironmentObject private var app: AppModel
    @State private var specs: [HiveSpec] = []
    @State private var query = ""
    @State private var errorMessage: String?
    @State private var isLoading = true

    private var visibleSpecs: [HiveSpec] {
        guard !query.isEmpty else { return specs }
        return specs.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.summary?.localizedCaseInsensitiveContains(query) ?? false)
                || $0.body.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && specs.isEmpty {
                    ProgressView("Loading Specs…")
                } else if let errorMessage, specs.isEmpty {
                    ContentUnavailableView(
                        "Specs could not load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if visibleSpecs.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(visibleSpecs) { spec in
                        NavigationLink(value: spec) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("#\(spec.number)")
                                        .foregroundStyle(.secondary)
                                    Text(spec.title)
                                        .font(.headline)
                                    if spec.hasNewActivity {
                                        Circle()
                                            .fill(.indigo)
                                            .frame(width: 7, height: 7)
                                            .accessibilityLabel("New activity")
                                    }
                                }
                                if let summary = spec.summary, !summary.isEmpty {
                                    Text(summary)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Text(readable(spec.status))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .navigationDestination(for: HiveSpec.self) { spec in
                        SpecDetailView(spec: spec)
                    }
                }
            }
            .navigationTitle("Specs")
            .searchable(text: $query, prompt: "Search Specs")
            .refreshable { await reload() }
            .task { await reload() }
        }
    }

    private func reload() async {
        guard specs.isEmpty || !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            specs = try await app.loadSpecs()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SpecDetailView: View {
    let spec: HiveSpec

    var body: some View {
        List {
            Section {
                LabeledContent("Status", value: readable(spec.status))
                LabeledContent("Visibility", value: readable(spec.visibility))
                LabeledContent("Revision", value: String(spec.revision))
            }

            if let summary = spec.summary, !summary.isEmpty {
                Section("Summary") {
                    Text(summary)
                }
            }

            Section("Proposal") {
                MarkdownView(source: spec.body)
                    .textSelection(.enabled)
            }

            if !spec.domains.isEmpty {
                Section("Domains") {
                    ForEach(spec.domains) { domain in
                        Label(domain.name, systemImage: "square.stack.3d.up")
                    }
                }
            }
        }
        .navigationTitle("#\(spec.number) \(spec.title)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DropListView: View {
    @EnvironmentObject private var app: AppModel
    @State private var drops: [HiveDrop] = []
    @State private var query = ""
    @State private var errorMessage: String?
    @State private var isLoading = true

    private var visibleDrops: [HiveDrop] {
        guard !query.isEmpty else { return drops }
        return drops.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.body?.localizedCaseInsensitiveContains(query) ?? false)
                || ($0.version?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && drops.isEmpty {
                    ProgressView("Loading Drops…")
                } else if let errorMessage, drops.isEmpty {
                    ContentUnavailableView(
                        "Drops could not load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if visibleDrops.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(visibleDrops) { drop in
                        NavigationLink(value: drop) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(drop.title)
                                    .font(.headline)
                                HStack(spacing: 8) {
                                    Text(readable(drop.sourceType))
                                    if let version = drop.version, !version.isEmpty {
                                        Text("•")
                                        Text(version)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .navigationDestination(for: HiveDrop.self) { drop in
                        DropDetailView(drop: drop)
                    }
                }
            }
            .navigationTitle("Drops")
            .searchable(text: $query, prompt: "Search Drops")
            .refreshable { await reload() }
            .task { await reload() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        DropDigestListView()
                    } label: {
                        Label("Weekly digests", systemImage: "newspaper")
                    }
                }
            }
        }
    }

    private func reload() async {
        guard drops.isEmpty || !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            drops = try await app.loadDrops()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct DropDetailView: View {
    let drop: HiveDrop

    var body: some View {
        List {
            Section {
                LabeledContent("Source", value: readable(drop.sourceType))
                if let version = drop.version, !version.isEmpty {
                    LabeledContent("Version", value: version)
                }
                if let publishedAt = drop.publishedAt {
                    LabeledContent("Published", value: published(publishedAt))
                }
            }

            if let body = drop.body, !body.isEmpty {
                Section("Update") {
                    MarkdownView(source: body)
                        .textSelection(.enabled)
                }
            }

            if !drop.domains.isEmpty {
                Section("Domains") {
                    ForEach(drop.domains) { domain in
                        Label(domain.name, systemImage: "square.stack.3d.up")
                    }
                }
            }

            if let url = URL(string: drop.url) {
                Section {
                    Link(destination: url) {
                        Label("Open original", systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .navigationTitle("#\(drop.number) \(drop.title)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DropDigestListView: View {
    @EnvironmentObject private var app: AppModel
    @State private var digests: [DropDigest] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading && digests.isEmpty {
                ProgressView("Loading weekly digests…")
            } else if let errorMessage, digests.isEmpty {
                ContentUnavailableView(
                    "Weekly digests could not load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if digests.isEmpty {
                ContentUnavailableView(
                    "No weekly digests",
                    systemImage: "newspaper",
                    description: Text("Narrated editions will appear after they are published.")
                )
            } else {
                List(digests) { digest in
                    NavigationLink {
                        DropDigestDetailView(digest: digest)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(digest.title)
                                .font(.headline)
                            Text(digest.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            HStack(spacing: 8) {
                                Text(weekRange(digest.weekStart, digest.weekEnd))
                                Text("•")
                                Text("\(digest.dropCount) Drops")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Weekly digests")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async {
        guard digests.isEmpty || !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            digests = try await app.loadDropDigests()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct DropDigestDetailView: View {
    let digest: DropDigest

    var body: some View {
        List {
            Section {
                LabeledContent("Week", value: weekRange(digest.weekStart, digest.weekEnd))
                LabeledContent("Drops", value: String(digest.dropCount))
                LabeledContent("Published", value: published(digest.publishedAt))
            }

            Section("Summary") {
                Text(digest.summary)
            }

            Section("Edition") {
                MarkdownView(source: digest.body)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle(digest.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AccountView: View {
    @EnvironmentObject private var app: AppModel
    @State private var isSigningOut = false

    var body: some View {
        NavigationStack {
            List {
                Section("Signed in as") {
                    if let user = app.user {
                        LabeledContent("Email", value: user.email)
                        LabeledContent("Role", value: readable(user.role))
                    }
                    if let server = app.server {
                        LabeledContent("Hive", value: server)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        isSigningOut = true
                        Task {
                            await app.signOut()
                            isSigningOut = false
                        }
                    } label: {
                        HStack {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            Spacer()
                            if isSigningOut { ProgressView() }
                        }
                    }
                    .disabled(isSigningOut)
                }
            }
            .navigationTitle("Account")
        }
    }
}

private func readable(_ value: String) -> String {
    switch value.lowercased() {
    case "github", "github_release": "GitHub Release"
    case "rss": "RSS"
    default: value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private func published(_ value: String) -> String {
    guard let date = ISO8601DateFormatter().date(from: value) else { return value }
    return date.formatted(date: .abbreviated, time: .shortened)
}

private func weekRange(_ start: String, _ end: String) -> String {
    let input = DateFormatter()
    input.locale = Locale(identifier: "en_US_POSIX")
    input.dateFormat = "yyyy-MM-dd"
    guard let startDate = input.date(from: start), let endDate = input.date(from: end) else {
        return "\(start) – \(end)"
    }
    return "\(startDate.formatted(.dateTime.month(.abbreviated).day())) – \(endDate.formatted(.dateTime.month(.abbreviated).day().year()))"
}

private struct MarkdownView: View {
    private let blocks: [MarkdownBlock]

    init(source: String) {
        blocks = MarkdownBlock.parse(source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(blocks) { block in
                switch block.content {
                case let .heading(level, text):
                    Text(inlineMarkdown(text))
                        .font(headingFont(level))
                        .fontWeight(.semibold)
                        .padding(.top, level == 1 ? 4 : 8)
                case let .paragraph(text):
                    Text(inlineMarkdown(text))
                        .font(.body)
                case let .list(items, ordered):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(ordered ? "\(index + 1)." : "•")
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: ordered ? 20 : 8, alignment: .trailing)
                                Text(inlineMarkdown(item))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("markdown-content")
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2
        case 2: .headline
        default: .subheadline
        }
    }

    private func inlineMarkdown(_ source: String) -> AttributedString {
        (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)
    }
}

private struct MarkdownBlock: Identifiable {
    enum Content {
        case heading(level: Int, text: String)
        case paragraph(String)
        case list(items: [String], ordered: Bool)
    }

    let id = UUID()
    let content: Content

    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                index += 1
                continue
            }

            if let heading = heading(line) {
                blocks.append(MarkdownBlock(content: .heading(level: heading.level, text: heading.text)))
                index += 1
                continue
            }

            if let item = listItem(line) {
                var items = [item.text]
                index += 1
                while index < lines.count,
                      let next = listItem(lines[index].trimmingCharacters(in: .whitespaces)),
                      next.ordered == item.ordered {
                    items.append(next.text)
                    index += 1
                }
                blocks.append(MarkdownBlock(content: .list(items: items, ordered: item.ordered)))
                continue
            }

            var paragraph = [line]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || heading(next) != nil || listItem(next) != nil { break }
                paragraph.append(next)
                index += 1
            }
            blocks.append(MarkdownBlock(content: .paragraph(paragraph.joined(separator: " "))))
        }

        return blocks
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let markers = line.prefix { $0 == "#" }
        guard !markers.isEmpty,
              markers.count <= 6,
              line.dropFirst(markers.count).first == " " else { return nil }
        return (markers.count, String(line.dropFirst(markers.count + 1)))
    }

    private static func listItem(_ line: String) -> (ordered: Bool, text: String)? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return (false, String(line.dropFirst(2)))
        }

        guard let period = line.firstIndex(of: "."),
              period != line.startIndex,
              line[line.startIndex..<period].allSatisfy(\.isNumber) else { return nil }
        let textStart = line.index(after: period)
        guard textStart < line.endIndex, line[textStart] == " " else { return nil }
        return (true, String(line[line.index(after: textStart)...]))
    }
}
