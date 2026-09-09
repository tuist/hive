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
            HomeOverviewView()
                .tabItem { Label("Home", systemImage: "house") }
            ErrorsListView()
                .tabItem { Label("Errors", systemImage: "exclamationmark.triangle") }
            SpecListView()
                .tabItem { Label("Specs", systemImage: "doc.text") }
            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .tint(.indigo)
        .accessibilityIdentifier("main-navigation")
    }
}

struct HomeOverviewView: View {
    @EnvironmentObject private var app: AppModel
    @State private var issues: [HiveErrorIssue] = []
    @State private var specs: [HiveSpec] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    private var unresolvedIssues: [HiveErrorIssue] {
        issues.filter { $0.status.lowercased() == "unresolved" }
    }

    private var specsNeedingAttention: [HiveSpec] {
        specs.filter { $0.hasNewActivity }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && issues.isEmpty && specs.isEmpty {
                    ProgressView("Loading Hive…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, issues.isEmpty, specs.isEmpty {
                    ContentUnavailableView(
                        "Overview could not load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else {
                    List {
                        Section {
                            HomeHeader(
                                greeting: greeting,
                                userName: app.user?.name ?? app.user?.email,
                                server: app.server
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }

                        Section("Needs attention") {
                            NavigationLink {
                                ErrorsListView()
                            } label: {
                                AttentionRow(
                                    icon: "exclamationmark.triangle.fill",
                                    tint: unresolvedIssues.isEmpty ? .green : .red,
                                    title: "Unresolved errors",
                                    detail: unresolvedIssues.isEmpty
                                        ? "All caught up"
                                        : "\(unresolvedIssues.count) open"
                                )
                            }

                            NavigationLink {
                                SpecListView()
                            } label: {
                                AttentionRow(
                                    icon: "doc.text.magnifyingglass",
                                    tint: specsNeedingAttention.isEmpty ? .green : .indigo,
                                    title: "Specs with new activity",
                                    detail: specsNeedingAttention.isEmpty
                                        ? "Nothing new"
                                        : "\(specsNeedingAttention.count) updated"
                                )
                            }
                        }

                        if !unresolvedIssues.isEmpty {
                            Section("Recent errors") {
                                ForEach(unresolvedIssues.prefix(3)) { issue in
                                    NavigationLink {
                                        ErrorIssueDetailView(issue: issue)
                                    } label: {
                                        HomeErrorRow(issue: issue)
                                    }
                                }
                            }
                        }

                        if !specsNeedingAttention.isEmpty {
                            Section("Specs with new activity") {
                                ForEach(specsNeedingAttention.prefix(3)) { spec in
                                    NavigationLink {
                                        SpecDetailView(spec: spec)
                                    } label: {
                                        HomeSpecRow(spec: spec)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Hive")
            .refreshable { await reload(force: true) }
            .task { await reload(force: false) }
        }
    }

    private func reload(force: Bool) async {
        if !force, !issues.isEmpty || !specs.isEmpty { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let issuesFetch = app.loadErrors()
            async let specsFetch = app.loadSpecs()
            issues = try await issuesFetch
            specs = try await specsFetch
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct HomeHeader: View {
    let greeting: String
    let userName: String?
    let server: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.title2.weight(.semibold))
            if let userName {
                Text(userName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let server, let host = URL(string: server)?.host() {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                    Text(host)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AttentionRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct HomeErrorRow: View {
    let issue: HiveErrorIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(issue.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(issue.level.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
                Text("•")
                Text("\(issue.eventCount) event\(issue.eventCount == 1 ? "" : "s")")
                if let projectName = issue.projectName, !projectName.isEmpty {
                    Text("•")
                    Text(projectName)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct HomeSpecRow: View {
    let spec: HiveSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("#\(spec.number)")
                    .foregroundStyle(.secondary)
                Text(spec.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
            }
            if let summary = spec.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
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

struct ErrorsListView: View {
    @EnvironmentObject private var app: AppModel
    @State private var issues: [HiveErrorIssue] = []
    @State private var query = ""
    @State private var errorMessage: String?
    @State private var isLoading = true

    private var visibleIssues: [HiveErrorIssue] {
        guard !query.isEmpty else { return issues }
        return issues.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.culprit?.localizedCaseInsensitiveContains(query) ?? false)
                || ($0.projectName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && issues.isEmpty {
                    ProgressView("Loading Errors…")
                } else if let errorMessage, issues.isEmpty {
                    ContentUnavailableView(
                        "Errors could not load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if visibleIssues.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if visibleIssues.isEmpty {
                    ContentUnavailableView(
                        "No errors captured",
                        systemImage: "checkmark.seal",
                        description: Text("New unhandled exceptions from your projects will appear here.")
                    )
                } else {
                    List(visibleIssues) { issue in
                        NavigationLink(value: issue) {
                            ErrorIssueRow(issue: issue)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .navigationDestination(for: HiveErrorIssue.self) { issue in
                        ErrorIssueDetailView(issue: issue)
                    }
                }
            }
            .navigationTitle("Errors")
            .searchable(text: $query, prompt: "Search Errors")
            .refreshable { await reload() }
            .task { await reload() }
        }
    }

    private func reload() async {
        guard issues.isEmpty || !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            issues = try await app.loadErrors()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ErrorIssueRow: View {
    let issue: HiveErrorIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LevelBadge(level: issue.level)
                Text(issue.title)
                    .font(.headline)
                    .lineLimit(2)
            }
            if let culprit = issue.culprit, !culprit.isEmpty {
                Text(culprit)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 8) {
                if let projectName = issue.projectName, !projectName.isEmpty {
                    Text(projectName)
                    Text("•")
                }
                Text("\(issue.eventCount) event\(issue.eventCount == 1 ? "" : "s")")
                if let lastSeen = relativeDate(issue.lastSeen) {
                    Text("•")
                    Text(lastSeen)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ErrorIssueDetailView: View {
    let issue: HiveErrorIssue

    var body: some View {
        List {
            Section {
                LabeledContent("Level", value: readable(issue.level))
                LabeledContent("Status", value: readable(issue.status))
                LabeledContent("Events", value: String(issue.eventCount))
                if let platform = issue.platform, !platform.isEmpty {
                    LabeledContent("Platform", value: platform)
                }
                if let projectName = issue.projectName, !projectName.isEmpty {
                    LabeledContent("Project", value: projectName)
                }
                if let environment = issue.environment, !environment.isEmpty {
                    LabeledContent("Environment", value: environment)
                }
                if let release = issue.release, !release.isEmpty {
                    LabeledContent("Release", value: release)
                }
            }

            if issue.exceptionType != nil || issue.exceptionValue != nil {
                Section("Exception") {
                    if let type = issue.exceptionType, !type.isEmpty {
                        LabeledContent("Type", value: type)
                    }
                    if let value = issue.exceptionValue, !value.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Message")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(value)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if issue.topFrameFunction != nil || issue.topFrameFilename != nil {
                Section("Top frame") {
                    if let function = issue.topFrameFunction, !function.isEmpty {
                        LabeledContent("Function") {
                            Text(function)
                                .font(.callout.monospaced())
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if let filename = issue.topFrameFilename, !filename.isEmpty {
                        LabeledContent("File") {
                            Text(filename)
                                .font(.callout.monospaced())
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                    }
                }
            }

            if let culprit = issue.culprit, !culprit.isEmpty {
                Section("Culprit") {
                    Text(culprit)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            }

            Section("Timeline") {
                if let firstSeen = issue.firstSeen {
                    LabeledContent("First seen", value: absoluteDate(firstSeen))
                }
                if let lastSeen = issue.lastSeen {
                    LabeledContent("Last seen", value: absoluteDate(lastSeen))
                }
            }

            if let fingerprint = issue.fingerprint, !fingerprint.isEmpty {
                Section("Identity") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Fingerprint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(fingerprint)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(3)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 2)
                }
            }

            if let dashboard = issue.dashboardURL, let url = URL(string: dashboard) {
                Section {
                    Link(destination: url) {
                        Label("Open in Hive", systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .navigationTitle(issue.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func absoluteDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter.hive.date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct LevelBadge: View {
    let level: String

    private var background: Color {
        switch level.lowercased() {
        case "fatal", "error": .red.opacity(0.15)
        case "warning": .orange.opacity(0.15)
        case "info": .blue.opacity(0.15)
        default: .gray.opacity(0.15)
        }
    }

    private var foreground: Color {
        switch level.lowercased() {
        case "fatal", "error": .red
        case "warning": .orange
        case "info": .blue
        default: .secondary
        }
    }

    var body: some View {
        Text(level.uppercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }
}

private func relativeDate(_ value: String?) -> String? {
    guard let value, let date = ISO8601DateFormatter.hive.date(from: value) else { return nil }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}

private extension ISO8601DateFormatter {
    static let hive: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
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
