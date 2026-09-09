import SwiftUI

struct HiveErrorsView: View {
    @EnvironmentObject private var account: HiveAccountStore
    @EnvironmentObject private var overview: HiveOverviewStore

    @State private var selectedIssue: HiveErrorIssue?
    @State private var query = ""

    private var visibleIssues: [HiveErrorIssue] {
        guard !query.isEmpty else { return overview.issues }
        return overview.issues.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.culprit?.localizedCaseInsensitiveContains(query) ?? false)
                || ($0.projectName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        Group {
            if !account.isSignedIn {
                HiveErrorsSignInView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if overview.isLoading, overview.issues.isEmpty {
                ProgressView("Loading Errors…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = overview.errorMessage, overview.issues.isEmpty {
                ContentUnavailableView(
                    "Errors could not load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .navigationTitle("Errors")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await overview.reload(using: account) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!account.isSignedIn || overview.isLoading)
            }
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            List(selection: $selectedIssue) {
                if visibleIssues.isEmpty {
                    Text(query.isEmpty ? "No captured errors yet." : "No matches.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleIssues) { issue in
                        HiveErrorIssueRow(issue: issue)
                            .tag(issue)
                    }
                }
            }
            .listStyle(.inset)
            .searchable(text: $query, placement: .sidebar, prompt: "Search errors")
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 460)

            Divider()

            if let issue = selectedIssue ?? visibleIssues.first {
                HiveErrorIssueDetailView(issue: issue)
                    .id(issue.id)
            } else {
                ContentUnavailableView(
                    "Select an error",
                    systemImage: "list.bullet.indent",
                    description: Text("Pick an issue on the left to inspect it.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct HiveErrorsSignInView: View {
    @EnvironmentObject private var account: HiveAccountStore

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.orange)
                Text("Sign in to view errors")
                    .font(.title2.weight(.semibold))
                Text("Connect the app to your Hive deployment to browse captured error issues.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Hive address")
                    .font(.subheadline.weight(.semibold))

                TextField(
                    "Hive address",
                    text: $account.pendingServer,
                    prompt: Text("https://hive.example.com")
                )
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onSubmit { account.signIn() }

                if let error = account.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    account.signIn()
                } label: {
                    HStack {
                        if account.isSigningIn {
                            ProgressView().controlSize(.small)
                        }
                        Text(account.isSigningIn ? "Connecting…" : "Continue")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    account.isSigningIn
                        || account.pendingServer.trimmingCharacters(in: .whitespaces).isEmpty
                )

                Label(
                    "Hive opens your browser to sign in securely.",
                    systemImage: "lock.shield"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
            .frame(maxWidth: 420)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.quaternary, lineWidth: 0.5)
            )

            Spacer(minLength: 0)
        }
        .padding(32)
    }
}

private struct HiveErrorIssueRow: View {
    let issue: HiveErrorIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HiveErrorLevelBadge(level: issue.level)
                Text(issue.title)
                    .font(.headline)
                    .lineLimit(2)
            }
            if let culprit = issue.culprit, !culprit.isEmpty {
                Text(culprit)
                    .font(.callout.monospaced())
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
                if let lastSeen = hiveRelativeDate(issue.lastSeen) {
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

struct HiveErrorIssueDetailView: View {
    let issue: HiveErrorIssue

    private var hasException: Bool {
        (issue.exceptionType?.isEmpty == false) || (issue.exceptionValue?.isEmpty == false)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        HiveErrorLevelBadge(level: issue.level)
                        Text(readable(issue.status))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(issue.title)
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)
                    if let culprit = issue.culprit, !culprit.isEmpty {
                        Text(culprit)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
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
                    if let firstSeen = issue.firstSeen {
                        LabeledContent("First seen", value: hiveAbsoluteDate(firstSeen))
                    }
                    if let lastSeen = issue.lastSeen {
                        LabeledContent("Last seen", value: hiveAbsoluteDate(lastSeen))
                    }
                }

                if hasException {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Exception")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let type = issue.exceptionType, !type.isEmpty {
                            Text(type)
                                .font(.callout.weight(.semibold))
                                .textSelection(.enabled)
                        }
                        if let value = issue.exceptionValue, !value.isEmpty {
                            Text(value)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                if issue.topFrameFunction != nil || issue.topFrameFilename != nil {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Top frame")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let function = issue.topFrameFunction, !function.isEmpty {
                            Text(function)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }
                        if let filename = issue.topFrameFilename, !filename.isEmpty {
                            Text(filename)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                    }
                }

                if let fingerprint = issue.fingerprint, !fingerprint.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Fingerprint")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(fingerprint)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(3)
                            .truncationMode(.middle)
                    }
                }

                if let dashboard = issue.dashboardURL, let url = URL(string: dashboard) {
                    Divider()
                    Link(destination: url) {
                        Label("Open in Hive", systemImage: "arrow.up.right.square")
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct HiveErrorLevelBadge: View {
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

private func hiveRelativeDate(_ value: String?) -> String? {
    guard let value, let date = hiveIsoDateFormatter.date(from: value) else { return nil }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}

private func hiveAbsoluteDate(_ value: String) -> String {
    guard let date = hiveIsoDateFormatter.date(from: value) else { return value }
    return date.formatted(date: .abbreviated, time: .shortened)
}

private func readable(_ value: String) -> String {
    value.replacingOccurrences(of: "_", with: " ").capitalized
}

private let hiveIsoDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()
