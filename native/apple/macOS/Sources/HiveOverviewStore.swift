import Foundation
import SwiftUI

@MainActor
final class HiveOverviewStore: ObservableObject {
    @Published private(set) var issues: [HiveErrorIssue] = []
    @Published private(set) var specs: [HiveSpec] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    var unresolvedIssues: [HiveErrorIssue] {
        issues.filter { $0.status.lowercased() == "unresolved" }
    }

    var specsNeedingAttention: [HiveSpec] {
        specs.filter { $0.hasNewActivity }
    }

    var unresolvedErrorsCount: Int { unresolvedIssues.count }
    var specsNeedingAttentionCount: Int { specsNeedingAttention.count }

    func reload(using account: HiveAccountStore) async {
        guard account.isSignedIn else {
            issues = []
            specs = []
            errorMessage = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            async let issuesFetch = account.loadErrors()
            async let specsFetch = account.loadSpecs()
            issues = try await issuesFetch
            specs = try await specsFetch
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        issues = []
        specs = []
        errorMessage = nil
    }
}
