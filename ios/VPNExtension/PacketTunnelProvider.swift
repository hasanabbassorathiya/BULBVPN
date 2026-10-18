import NetworkExtension
import OpenVPNAdapter
import os.log

extension NEPacketTunnelFlow: OpenVPNAdapterPacketFlow {}

/// OpenVPN packet tunnel. A live session stays up on both Wi-Fi and cellular.
/// Reachability only nudges a tunnel that has already dropped, which is the
/// failure we saw when an Iranian network change tore down a working session.
class PacketTunnelProvider: NEPacketTunnelProvider {
    private static let vpnLog = OSLog(subsystem: "app.bulbvpn.com", category: "VPN")

    private lazy var vpnAdapter: OpenVPNAdapter = {
        let adapter = OpenVPNAdapter()
        adapter.delegate = self
        return adapter
    }()

    private let vpnReachability = OpenVPNReachability()
    private var startHandler: ((Error?) -> Void)?
    private var stopHandler: (() -> Void)?
    private var groupIdentifier: String?
    private var tunnelUp = false
    private var sawReachability = false

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard
            let protocolConfiguration = protocolConfiguration as? NETunnelProviderProtocol,
            let providerConfiguration = protocolConfiguration.providerConfiguration,
            let ovpnFileContent = providerConfiguration["config"] as? Data
        else {
            completionHandler(OpenVPNAdapterError.configurationFailure)
            return
        }
        if let groupData = providerConfiguration["groupIdentifier"] as? Data {
            groupIdentifier = String(decoding: groupData, as: UTF8.self)
        }

        let configuration = OpenVPNConfiguration()
        configuration.fileContent = ovpnFileContent
        configuration.tunPersist = true

        let evaluation: OpenVPNConfigurationEvaluation
        do {
            evaluation = try vpnAdapter.apply(configuration: configuration)
        } catch {
            completionHandler(error)
            return
        }

        if !evaluation.autologin {
            guard
                let username = options?["username"] as? String,
                let password = options?["password"] as? String
            else {
                completionHandler(OpenVPNAdapterError.configurationFailure)
                return
            }
            let credentials = OpenVPNCredentials()
            credentials.username = username
            credentials.password = password
            do {
                try vpnAdapter.provide(credentials: credentials)
            } catch {
                completionHandler(error)
                return
            }
        }

        vpnReachability.startTracking { [weak self] status in
            self?.networkBecameReachable(status)
        }
        startHandler = completionHandler
        vpnAdapter.connect(using: packetFlow)
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        stopHandler = completionHandler
        tunnelUp = false
        if vpnReachability.isTracking {
            vpnReachability.stopTracking()
        }
        vpnAdapter.disconnect()
    }

    override func handleAppMessage(
        _ messageData: Data,
        completionHandler: ((Data?) -> Void)? = nil
    ) {
        guard let completionHandler else { return }
        guard String(data: messageData, encoding: .utf8) == "OPENVPN_STATS" else {
            completionHandler(nil)
            return
        }
        let stats = vpnAdapter.interfaceStatistics
        let json = "{\"totalDownload\":\(stats.bytesIn),\"totalUpload\":\(stats.bytesOut),\"latestHandshake\":0}"
        completionHandler(json.data(using: .utf8))
    }

    /// First callback is the path we are already dialing. Later callbacks
    /// cover Wi-Fi and cellular. A tunnel that is still up is left alone.
    private func networkBecameReachable(_ status: OpenVPNReachabilityStatus) {
        let online = status == .reachableViaWiFi || status == .reachableViaWWAN
        let first = !sawReachability
        sawReachability = true
        guard !first, online, !tunnelUp else { return }
        os_log("Network is back and the tunnel is down; reconnecting", log: Self.vpnLog, type: .info)
        vpnAdapter.reconnect(afterTimeInterval: 2)
    }
}

extension PacketTunnelProvider: OpenVPNAdapterDelegate {
    func openVPNAdapter(
        _ openVPNAdapter: OpenVPNAdapter,
        configureTunnelWithNetworkSettings networkSettings: NEPacketTunnelNetworkSettings?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        networkSettings?.dnsSettings?.matchDomains = [""]
        setTunnelNetworkSettings(networkSettings, completionHandler: completionHandler)
    }

    func openVPNAdapter(
        _ openVPNAdapter: OpenVPNAdapter,
        handleEvent event: OpenVPNAdapterEvent,
        message: String?
    ) {
        switch event {
        case .connected:
            tunnelUp = true
            if reasserting { reasserting = false }
            UserDefaults(suiteName: groupIdentifier)?.set(Date(), forKey: "connected_on")
            startHandler?(nil)
            startHandler = nil
        case .disconnected:
            tunnelUp = false
            if vpnReachability.isTracking {
                vpnReachability.stopTracking()
            }
            stopHandler?()
            stopHandler = nil
        case .reconnecting:
            tunnelUp = false
            reasserting = true
        default:
            break
        }
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleError error: Error) {
        let fatal = (error as NSError).userInfo[OpenVPNAdapterErrorFatalKey] as? Bool ?? false
        guard fatal else { return }
        tunnelUp = false
        if vpnReachability.isTracking {
            vpnReachability.stopTracking()
        }
        if let startHandler {
            startHandler(error)
            self.startHandler = nil
        } else {
            cancelTunnelWithError(error)
        }
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleLogMessage logMessage: String) {
        os_log("%{public}@", log: Self.vpnLog, type: .info, logMessage)
    }
}
