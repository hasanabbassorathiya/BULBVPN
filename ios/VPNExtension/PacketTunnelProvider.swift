//
//  PacketTunnelProvider.swift
//  VPNExtension
//
//  OpenVPN tunnel provider for BULBVPN.
//  Matches the openvpn_flutter 1.3.4 example extension exactly.
//

import NetworkExtension
import OpenVPNAdapter
import os.log

extension NEPacketTunnelFlow: OpenVPNAdapterPacketFlow {}

class PacketTunnelProvider: NEPacketTunnelProvider {

    lazy var vpnAdapter: OpenVPNAdapter = {
        let adapter = OpenVPNAdapter()
        adapter.delegate = self
        return adapter
    }()

    let vpnReachability = OpenVPNReachability()
    var providerManager: NETunnelProviderManager!

    var startHandler: ((Error?) -> Void)?
    var stopHandler: (() -> Void)?
    var groupIdentifier: String?

    static var connectionIndex = 0
    static var timeOutEnabled = true

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard
            let protocolConfiguration = protocolConfiguration as? NETunnelProviderProtocol,
            let providerConfiguration = protocolConfiguration.providerConfiguration
        else {
            completionHandler(NEPacketTunnelProviderError(.configurationInvalid, userInfo: [:]))
            return
        }
        guard let ovpnFileContent: Data = providerConfiguration["config"] as? Data else {
            completionHandler(NEPacketTunnelProviderError(.configurationInvalid, userInfo: [:]))
            return
        }
        guard let groupIdentifierData: Data = providerConfiguration["groupIdentifier"] as? Data else {
            completionHandler(NEPacketTunnelProviderError(.configurationInvalid, userInfo: [:]))
            return
        }
        self.groupIdentifier = String(decoding: groupIdentifierData, as: UTF8.self)

        let configuration = OpenVPNConfiguration()
        configuration.fileContent = ovpnFileContent
        configuration.tunPersist = false

        let properties: OpenVPNConfigurationEvaluation
        do {
            properties = try vpnAdapter.apply(configuration: configuration)
        } catch {
            completionHandler(error)
            return
        }

        if !properties.autologin {
            guard let username = options?["username"] as? String, let password = options?["password"] as? String else {
                completionHandler(NEPacketTunnelProviderError(.configurationInvalid, userInfo: [:]))
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
            guard status == .reachableViaWiFi else { return }
            // Bounded: only reconnect on reachability change, never loop.
            self?.vpnAdapter.reconnect(afterTimeInterval: 5)
        }
        startHandler = completionHandler
        vpnAdapter.connect(using: packetFlow)
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stopHandler = completionHandler
        if vpnReachability.isTracking {
            vpnReachability.stopTracking()
        }
        vpnAdapter.disconnect()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        if String(data: messageData, encoding: .utf8) == "OPENVPN_STATS" {
            var toSave = ""
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let connectedOn = UserDefaults(suiteName: groupIdentifier)?.string(forKey: "connected_on") ?? ""
            toSave += connectedOn
            toSave += "_"
            toSave += String(vpnAdapter.interfaceStatistics.packetsIn)
            toSave += "_"
            toSave += String(vpnAdapter.interfaceStatistics.packetsOut)
        }
        completionHandler?(nil)
    }
}

extension PacketTunnelProvider: OpenVPNAdapterDelegate {
    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, configureTunnelWithNetworkSettings networkSettings: NEPacketTunnelNetworkSettings?, completionHandler: @escaping (Error?) -> Void) {
        // Settings are owned by the adapter. This path only reports that
        // configuration finished; it does not invent a loopback remote.
        _ = networkSettings
        completionHandler(nil)
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleEvent event: OpenVPNAdapterEvent, message: String?) {
        switch event {
        case .connected:
            UserDefaults(suiteName: groupIdentifier)?.set(Date(), forKey: "connected_on")
            if let startHandler = startHandler {
                startHandler(nil)
                self.startHandler = nil
            }
        case .disconnected:
            if let stopHandler = stopHandler {
                if vpnReachability.isTracking {
                    vpnReachability.stopTracking()
                }
                stopHandler()
                self.stopHandler = nil
            }
        default:
            break
        }
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleError error: Error) {
        if let startHandler = startHandler {
            startHandler(error)
            self.startHandler = nil
        }
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleLogMessage logmessage: String) {
        os_log("%{public}@", log: OSLog(subsystem: "com.bulbvpn.app", category: "OpenVPN"), logmessage)
    }
}
