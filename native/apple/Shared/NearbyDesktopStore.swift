import Combine
import Foundation
import Network

struct NearbyDesktop: Identifiable, Hashable {
    let id: String
    let name: String
}

@MainActor
final class NearbyDesktopStore: ObservableObject {
    @Published private(set) var desktops = [NearbyDesktop]()

    private let queue = DispatchQueue(label: "dev.tuist.hive.work.nearby-desktops")
    #if os(macOS)
    private var listener: NWListener?
    #else
    private var browser: NWBrowser?
    #endif

    init() {
        #if os(macOS)
        startAdvertising()
        #else
        startBrowsing()
        #endif
    }

    deinit {
        #if os(macOS)
        listener?.cancel()
        #else
        browser?.cancel()
        #endif
    }

    #if os(macOS)
    private func startAdvertising() {
        do {
            let listener = try NWListener(using: .tcp, on: .any)
            listener.service = NWListener.Service(
                name: ProcessInfo.processInfo.hostName,
                type: "_tuist-hive._tcp"
            )
            listener.newConnectionHandler = { connection in
                connection.cancel()
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            listener = nil
        }
    }
    #else
    private func startBrowsing() {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: "_tuist-hive._tcp", domain: nil),
            using: parameters
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let desktops = results.compactMap { result -> NearbyDesktop? in
                guard case let .service(name, type, domain, _) = result.endpoint else {
                    return nil
                }
                return NearbyDesktop(
                    id: "\(name).\(type).\(domain)",
                    name: name
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            Task { @MainActor [weak self] in
                self?.desktops = desktops
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }
    #endif
}
