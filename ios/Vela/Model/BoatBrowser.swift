import Foundation
import Network

/// A base station found on the local network.
struct Boat: Identifiable, Hashable {
    /// The boat's name, as set in the base station's settings file.
    let name: String
    /// The base station's Bonjour host name, for example `MacBook-Pro.local`.
    let host: String
    /// The control service's port.
    let port: Int

    var id: String { name }

    var baseURL: URL? {
        URL(string: "http://\(host):\(port)")
    }
}

/// Browses Bonjour for Vela base stations.
///
/// `_vela._tcp` is the one permanent name the app and the base station share.
/// It is also declared in Info.plist, which iOS requires before it lets an app browse.
@MainActor
final class BoatBrowser {
    static let serviceType = "_vela._tcp"

    var onChange: (([Boat]) -> Void)?
    /// Set when iOS refuses the browse, which means Local Network access is off.
    var onProblem: ((String?) -> Void)?

    private var browser: NWBrowser?

    func start() {
        browser?.cancel()

        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: NWParameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let boats = Self.boats(from: results)
            Task { @MainActor in self?.onChange?(boats) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handle(state) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func handle(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            onProblem?(nil)
        case .waiting:
            // The usual cause is the Local Network permission being denied.
            onProblem?("Vela cannot search the network. Check that Local Network is allowed for Vela in Settings.")
        case .failed:
            onProblem?("Searching for boats stopped. Retrying.")
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.start()
            }
        default:
            break
        }
    }

    private nonisolated static func boats(from results: Set<NWBrowser.Result>) -> [Boat] {
        var found: [String: Boat] = [:]
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint,
                  case let .bonjour(txt) = result.metadata,
                  let host = txt["host"],
                  let portText = txt["port"], let port = Int(portText)
            else { continue }
            found[name] = Boat(name: txt["boat"] ?? name, host: host, port: port)
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
