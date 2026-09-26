//
//  NetworkMonitor.swift
//  Pitstop
//
//  Thin @Observable wrapper around NWPathMonitor that exposes live network
//  connectivity as a single Bool. Injected into the app environment so any
//  view can react to connectivity changes without Combine or NotificationCenter.
//
//  Design choices:
//    • NWPathMonitor fires on a private utility queue; the callback hops to
//      MainActor via Task so @Observable mutations always happen on the main
//      thread and SwiftUI re-renders correctly.
//    • Starts optimistically as `true` — the first NWPathMonitor callback
//      arrives within milliseconds and will correct this if needed.
//    • `deinit` cancels the monitor so resources are released when the
//      singleton is torn down (e.g. in unit tests).
//

import Network
import Observation

@Observable
final class NetworkMonitor {

    // MARK: - Observed State

    /// True when the device has at least one satisfied network path
    /// (Wi-Fi, Cellular, or Ethernet). False when fully offline.
    private(set) var isConnected: Bool = true

    // MARK: - Private

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.pitstop.NetworkMonitor", qos: .utility)

    // MARK: - Init / Deinit

    init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
