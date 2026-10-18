import NetworkExtension
import OpenVPNAdapter
import os.log

extension NEPacketTunnelFlow: OpenVPNAdapterPacketFlow {}

/// OpenVPN packet tunnel compiled into VPNExtension.appex.
///
/// openvpn_dart's configureVPN only puts the profile bytes under "config"
/// and starts the tunnel with an empty options dictionary. A required
/// groupIdentifier, or skipping setTunnelNetworkSettings, makes every
/// candidate fail before OpenVPN can finish.
class PacketTunnelProvider: NEPacketTunnelProvider {
    private static let vpnLog = OSLog(subsystem: "app.bulbvpn.com", category: "VPN")

    /// Append a line to the app-group log so it can be copied off the
    /// device with `devicectl` without a screen or live console.
    private func fileLog(_ message: String) {
        guard let dir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.bulbvpn.app"
        ) else { return }
        let file = dir.appendingPathComponent("bulb-tunnel.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: file.path),
           let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: file)
        }
    }

    private static func configurationError(_ message: String) -> NSError {
        NSError(
            domain: OpenVPNAdapterErrorDomain,
            code: OpenVPNAdapterError.configurationFailure.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

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
    /// Only reconnect after a successful CONNECTED in this startTunnel session.
    /// Reachability often fires twice while the first handshake is still running;
    /// reconnecting then cancels it and leaves startHandler never called.
    private var everConnected = false
    /// OpenVPNAdapter emits a leftover DISCONNECTED when a new dial starts.
    /// Failing startTunnel on that event aborts a handshake that has not begun.
    private var sawConnecting = false
    private var startTimeoutWork: DispatchWorkItem?

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        os_log("startTunnel", log: Self.vpnLog, type: .info)
        fileLog("startTunnel")
        guard
            let protocolConfiguration = protocolConfiguration as? NETunnelProviderProtocol,
            let providerConfiguration = protocolConfiguration.providerConfiguration,
            let ovpnFileContent = providerConfiguration["config"] as? Data
        else {
            os_log("startTunnel missing config", log: Self.vpnLog, type: .error)
            fileLog("startTunnel missing config")
            completionHandler(Self.configurationError("Missing OpenVPN config"))
            return
        }
        if let groupData = providerConfiguration["groupIdentifier"] as? Data {
            groupIdentifier = String(decoding: groupData, as: UTF8.self)
        }

        let configuration = OpenVPNConfiguration()
        configuration.fileContent = ovpnFileContent
        // Match the openvpn_dart example: persist across reconnect only after
        // the first CONNECTED, not during the initial dial.
        configuration.tunPersist = false
        // VPN Gate is SoftEther OpenVPN. OpenVPN 3 refuses its TLS ciphers
        // (DHE-RSA-AES-CBC-SHA) unless this is set, so TCP connects and the
        // handshake never finishes.
        configuration.forceCiphersuitesAESCBC = true
        if let tls10 = OpenVPNMinTLSVersion(rawValue: 1) {
            configuration.minTLSVersion = tls10
        }
        configuration.compressionMode = .enabled
        configuration.info = true

        let evaluation: OpenVPNConfigurationEvaluation
        do {
            evaluation = try vpnAdapter.apply(configuration: configuration)
        } catch {
            os_log("apply failed: %{public}@", log: Self.vpnLog, type: .error, error.localizedDescription)
            fileLog("apply failed: \(error.localizedDescription)")
            completionHandler(error)
            return
        }
        os_log(
            "apply ok autologin=%{public}@",
            log: Self.vpnLog,
            type: .info,
            evaluation.autologin ? "true" : "false"
        )

        // Prefer options, then inline <auth-user-pass>. Provide them whenever
        // we have a pair — VPN Gate profiles often report autologin=false.
        let inline = Self.inlineCredentials(from: ovpnFileContent)
        let username = options?["username"] as? String ?? inline?.username
        let password = options?["password"] as? String ?? inline?.password
        if let username, let password {
            let credentials = OpenVPNCredentials()
            credentials.username = username
            credentials.password = password
            do {
                try vpnAdapter.provide(credentials: credentials)
                os_log("credentials provided", log: Self.vpnLog, type: .info)
            } catch {
                os_log("provide credentials failed: %{public}@", log: Self.vpnLog, type: .error, error.localizedDescription)
                completionHandler(error)
                return
            }
        } else if !evaluation.autologin {
            os_log("credentials missing", log: Self.vpnLog, type: .error)
            completionHandler(Self.configurationError("Missing OpenVPN credentials"))
            return
        }

        vpnReachability.startTracking { [weak self] status in
            self?.networkBecameReachable(status)
        }
        startHandler = completionHandler
        scheduleStartTimeout()
        vpnAdapter.connect(using: packetFlow)
        os_log("OpenVPNAdapter connect started", log: Self.vpnLog, type: .info)
        fileLog("OpenVPNAdapter connect started")
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        os_log("stopTunnel reason=%{public}d", log: Self.vpnLog, type: .info, reason.rawValue)
        cancelStartTimeout()
        stopHandler = completionHandler
        tunnelUp = false
        everConnected = false
        if vpnReachability.isTracking {
            vpnReachability.stopTracking()
        }
        vpnAdapter.disconnect()
    }

    /// Fail the NE start completion if OpenVPN never reaches CONNECTED.
    /// Without this, NEVPNStatus stays `.connecting` and the UI hangs on
    /// "opening tunnel" until the system eventually kills the extension.
    private func scheduleStartTimeout() {
        cancelStartTimeout()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let startHandler = self.startHandler else { return }
            os_log("startTunnel timed out waiting for CONNECTED", log: Self.vpnLog, type: .error)
            fileLog("startTunnel timed out waiting for CONNECTED")
            self.startHandler = nil
            self.tunnelUp = false
            if self.vpnReachability.isTracking {
                self.vpnReachability.stopTracking()
            }
            self.vpnAdapter.disconnect()
            startHandler(Self.configurationError("OpenVPN handshake timed out"))
        }
        startTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 22, execute: work)
    }

    private func cancelStartTimeout() {
        startTimeoutWork?.cancel()
        startTimeoutWork = nil
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

    /// Reconnect only after we have been CONNECTED once in this session.
    /// Mid-handshake reachability flaps must not call reconnect — that
    /// aborts the first dial and leaves startHandler unset forever.
    private func networkBecameReachable(_ status: OpenVPNReachabilityStatus) {
        let online = status == .reachableViaWiFi || status == .reachableViaWWAN
        guard everConnected, online, !tunnelUp else { return }
        os_log("Network is back and the tunnel is down; reconnecting", log: Self.vpnLog, type: .info)
        vpnAdapter.reconnect(afterTimeInterval: 2)
    }

    /// `<auth-user-pass>` body when the plugin starts the tunnel with no
    /// username or password in the options dictionary.
    private static func inlineCredentials(from ovpn: Data) -> (username: String, password: String)? {
        guard let text = String(data: ovpn, encoding: .utf8) else { return nil }
        guard let start = text.range(of: "<auth-user-pass>"),
              let end = text.range(of: "</auth-user-pass>") else {
            return nil
        }
        let body = text[start.upperBound..<end.lowerBound]
        let lines = body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2 else { return nil }
        return (String(lines[0]), String(lines[1]))
    }
}

extension PacketTunnelProvider: OpenVPNAdapterDelegate {
    func openVPNAdapter(
        _ openVPNAdapter: OpenVPNAdapter,
        configureTunnelWithNetworkSettings networkSettings: NEPacketTunnelNetworkSettings?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        os_log("setTunnelNetworkSettings", log: Self.vpnLog, type: .info)
        networkSettings?.dnsSettings?.matchDomains = [""]
        setTunnelNetworkSettings(networkSettings) { error in
            if let error {
                os_log("setTunnelNetworkSettings failed: %{public}@", log: Self.vpnLog, type: .error, error.localizedDescription)
            } else {
                os_log("setTunnelNetworkSettings ok", log: Self.vpnLog, type: .error)
            }
            completionHandler(error)
        }
    }

    func openVPNAdapter(
        _ openVPNAdapter: OpenVPNAdapter,
        handleEvent event: OpenVPNAdapterEvent,
        message: String?
    ) {
        let name: String
        switch event {
        case .connected: name = "CONNECTED"
        case .disconnected: name = "DISCONNECTED"
        case .connecting:
            name = "CONNECTING"
            sawConnecting = true
        case .reconnecting: name = "RECONNECTING"
        case .info: name = "INFO"
        default: name = "OTHER"
        }
        os_log("event %{public}@ %{public}@", log: Self.vpnLog, type: .error, name, message ?? "")
        fileLog("event \(name) \(message ?? "")")

        switch event {
        case .connected:
            cancelStartTimeout()
            tunnelUp = true
            everConnected = true
            if reasserting { reasserting = false }
            UserDefaults(suiteName: groupIdentifier)?.set(Date(), forKey: "connected_on")
            startHandler?(nil)
            startHandler = nil
        case .disconnected:
            tunnelUp = false
            if vpnReachability.isTracking {
                vpnReachability.stopTracking()
            }
            // A disconnect before CONNECTING is the previous session clearing.
            if let startHandler, sawConnecting {
                cancelStartTimeout()
                self.startHandler = nil
                startHandler(Self.configurationError("OpenVPN disconnected before CONNECTED"))
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
        os_log(
            "adapter error fatal=%{public}@ %{public}@",
            log: Self.vpnLog,
            type: .error,
            fatal ? "true" : "false",
            error.localizedDescription
        )
        fileLog("adapter error fatal=\(fatal) \(error.localizedDescription)")
        guard fatal else { return }
        cancelStartTimeout()
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
        os_log("%{public}@", log: Self.vpnLog, type: .error, logMessage)
        fileLog(logMessage)
    }
}
