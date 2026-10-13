import OpenVPNAdapter
import NetworkExtension
import os.log

class PacketTunnelProvider: OpenVPNAdapterPacketTunnelProvider {

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        os_log("Starting BULBVPN tunnel (macOS)...")

        guard let providerProtocol = protocolConfiguration as? NETunnelProviderProtocol,
              let providerConfig = providerProtocol.providerConfiguration,
              let configData = providerConfig["config"] as? Data,
              let configString = String(data: configData, encoding: .utf8),
              !configString.isEmpty else {
            os_log("❌ Missing or empty OpenVPN config")
            completionHandler(NSError(domain: "BULBVPN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing OpenVPN configuration"]))
            return
        }

        os_log("✅ OpenVPN config received (%d chars)", configString.count)

        let openVPNAdapter = OpenVPNAdapter()
        openVPNAdapter.delegate = self

        let properties: [String: Any] = [
            OpenVPNAdapter.configurationFile: configString,
            OpenVPNAdapter.disconnectOnSleep: false,
        ]

        openVPNAdapter.connect(with: properties)

        self.startCompletionHandler = completionHandler
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        os_log("Stopping BULBVPN tunnel (macOS) (reason: %d)", reason.rawValue)
        
        if let openVPNAdapter = self.openVPNAdapter {
            openVPNAdapter.disconnect()
        }
        
        self.stopCompletionHandler = completionHandler
    }

    override func handleAppMessage(
        _ messageData: Data,
        completionHandler: ((Data?) -> Void)?
    ) {
        guard let message = String(data: messageData, encoding: .utf8) else {
            completionHandler?(nil)
            return
        }

        os_log("Received app message (macOS): %@", message)

        if message == "OPENVPN_STATS",
           let openVPNAdapter = self.openVPNAdapter,
           let stats = openVPNAdapter.vpnStats {
            let statsString = "byteIn: \(stats.bytesIn), byteOut: \(stats.bytesOut), packetIn: \(stats.packetsIn), packetOut: \(stats.packetsOut)"
            let responseData = statsString.data(using: .utf8)
            completionHandler?(responseData)
        } else {
            completionHandler?(nil)
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        os_log("Tunnel going to sleep (macOS)...")
        completionHandler()
    }

    override func wake() {
        os_log("Tunnel waking up (macOS)...")
    }
}