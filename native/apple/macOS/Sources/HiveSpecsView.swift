import SwiftUI

struct HiveSpecsView: View {
    @EnvironmentObject private var account: HiveAccountStore
    @EnvironmentObject private var overview: HiveOverviewStore

    @State private var selectedSpec: HiveSpec?
    @State private var query = ""

    private var visibleSpecs: [HiveSpec] {
        guard !query.isEmpty else { return overview.specs }
        return overview.specs.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.summary?.localizedCaseInsensitiveContains(query) ?? false)
                || $0.body.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Group {
            if !account.isSignedIn {
                ContentUnavailableView(
                    "Sign in to see specs",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Connect the app to your Hive deployment to browse specifications.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if overview.isLoading, overview.specs.isEmpty {
                ProgressView("Loading Specs…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = overview.errorMessage, overview.specs.isEmpty {
                ContentUnavailableView(
                    "Specs could not load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .navigationTitle("Specs")
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
            List(selection: $selectedSpec) {
                if visibleSpecs.isEmpty {
                    Text(query.isEmpty ? "No specs yet." : "No matches.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleSpecs) { spec in
                        HiveSpecRow(spec: spec).tag(spec)
                    }
                }
            }
            .listStyle(.inset)
            .searchable(text: $query, placement: .sidebar, prompt: "Search specs")
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 460)

            Divider()

            if let spec = selectedSpec ?? visibleSpecs.first {
                HiveSpecDetailView(spec: spec).id(spec.id)
            } else {
                ContentUnavailableView(
                    "Select a spec",
                    systemImage: "doc.text",
                    description: Text("Pick a specification on the left to read it.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct HiveSpecRow: View {
    let spec: HiveSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("#\(spec.number)")
                    .foregroundStyle(.secondary)
                Text(spec.title)
                    .font(.headline)
                    .lineLimit(2)
                if spec.hasNewActivity {
                    Circle()
                        .fill(.indigo)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("New activity")
                }
            }
            if let summary = spec.summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(spec.status.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct HiveSpecDetailView: View {
    let spec: HiveSpec

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("#\(spec.number)")
                            .foregroundStyle(.secondary)
                        Text(spec.status.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(spec.title)
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)
                    if let summary = spec.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Visibility", value: spec.visibility.capitalized)
                    LabeledContent("Revision", value: String(spec.revision))
                }

                Divider()

                Text("Proposal")
                    .font(.headline)
                Text(spec.body)
                    .font(.callout)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
