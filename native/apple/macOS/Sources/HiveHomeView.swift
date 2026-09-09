import SwiftUI

struct HiveHomeView: View {
    @EnvironmentObject private var account: HiveAccountStore
    @EnvironmentObject private var overview: HiveOverviewStore

    var body: some View {
        Group {
            if !account.isSignedIn {
                ContentUnavailableView(
                    "Sign in to see your overview",
                    systemImage: "house",
                    description: Text("Connect the app to your Hive deployment to see what needs attention.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if overview.isLoading, overview.issues.isEmpty, overview.specs.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = overview.errorMessage, overview.issues.isEmpty, overview.specs.isEmpty {
                ContentUnavailableView(
                    "Overview could not load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if overview.unresolvedIssues.isEmpty, overview.specsNeedingAttention.isEmpty {
                ContentUnavailableView(
                    "You're all caught up",
                    systemImage: "checkmark.seal",
                    description: Text("No unresolved errors and no specs with new activity.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !overview.unresolvedIssues.isEmpty {
                        Section("Unresolved errors") {
                            ForEach(overview.unresolvedIssues.prefix(6)) { issue in
                                HomeIssueRow(issue: issue)
                            }
                        }
                    }

                    if !overview.specsNeedingAttention.isEmpty {
                        Section("Specs with new activity") {
                            ForEach(overview.specsNeedingAttention.prefix(6)) { spec in
                                HomeSpecRow(spec: spec)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Home")
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
}

private struct HomeIssueRow: View {
    let issue: HiveErrorIssue

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .imageScale(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title)
                    .font(.body)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(issue.level.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                    Text("·").foregroundStyle(.secondary)
                    Text("\(issue.eventCount) event\(issue.eventCount == 1 ? "" : "s")")
                    if let projectName = issue.projectName, !projectName.isEmpty {
                        Text("·").foregroundStyle(.secondary)
                        Text(projectName)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct HomeSpecRow: View {
    let spec: HiveSpec

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.indigo)
                .imageScale(.small)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("#\(spec.number)")
                        .foregroundStyle(.secondary)
                    Text(spec.title)
                        .lineLimit(2)
                }
                if let summary = spec.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
