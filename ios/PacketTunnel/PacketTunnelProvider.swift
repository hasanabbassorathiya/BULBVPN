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
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        var files: [URL] = []
        if let dir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.bulbvpn.app"
        ) {
            files.append(dir.appendingPathComponent("Library/Caches/bulb-tunnel.log"))
        }
        if let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first {
            files.append(caches.appendingPathComponent("bulb-tunnel.log"))
        }
        for file in files {
            if FileManager.default.fileExists(atPath: file.path),
               let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: file)
            }
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
    /// How many OpenVPN log lines have been kept this dial. iOS 16
    /// packet-tunnel jetsam is about 50 MB (tighter on 2 GB A9 iPads).
    private var retainedLogLines = 0

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        os_log("startTunnel", log: Self.vpnLog, type: .info)
        fileLog("startTunnel")
        // Fresh dial: clear leftover state from a prior candidate in this
        // extension process. Stale sawConnecting made a replayed DISCONNECTED
        // fail startTunnel before OpenVPN CONNECTING on the next attempt.
        cancelStartTimeout()
        startHandler = nil
        stopHandler = nil
        tunnelUp = false
        everConnected = false
        sawConnecting = false
        retainedLogLines = 0
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

        let prepared = Self.softEtherProfile(ovpnFileContent)
        let configuration = OpenVPNConfiguration()
        configuration.fileContent = prepared
        // Match the openvpn_dart example: persist across reconnect only after
        // the first CONNECTED, not during the initial dial.
        configuration.tunPersist = false
        // SoftEther tls-auth is client key-direction 1. Bidirectional (-1)
        // is the adapter default when the profile omits key-direction.
        configuration.keyDirection = 1
        // VPN Gate ships a dummy client cert. Sending it leaves SoftEther
        // waiting after VERIFY OK. Username/password is the real auth.
        configuration.disableClientCert = true
        // Keep mbed TLS quiet. Level 3 plus verb 4 filled the iOS 16
        // extension memory limit on iPad and the process was jetsam'd
        // before CONNECTED. The TLS 1.0 pin does not need the debug log.
        configuration.sslDebugLevel = 0
        if let tls10 = OpenVPNMinTLSVersion(rawValue: 1) {
            configuration.minTLSVersion = tls10
        }
        // Legacy allows the SHA1 opengw.net leaf. A profile "preferred"
        // would otherwise replace this.
        if let legacy = OpenVPNTLSCertProfile(rawValue: 0) {
            configuration.tlsCertProfile = legacy
        }
        configuration.compressionMode = .enabled
        configuration.info = true
        // Set last. mbed TLS used to let a profile tls-version-min undo this
        // flag; the adapter now re-applies it after the profile is parsed.
        configuration.forceCiphersuitesAESCBC = true

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
        let inline = Self.inlineCredentials(from: prepared)
        let username = options?["username"] as? String ?? inline?.username ?? "vpn"
        let password = options?["password"] as? String ?? inline?.password ?? "vpn"
        let credentials = OpenVPNCredentials()
        credentials.username = username
        credentials.password = password
        do {
            try vpnAdapter.provide(credentials: credentials)
            os_log("credentials provided", log: Self.vpnLog, type: .info)
            fileLog("credentials provided user=\(username)")
        } catch {
            os_log("provide credentials failed: %{public}@", log: Self.vpnLog, type: .error, error.localizedDescription)
            completionHandler(error)
            return
        }

        vpnReachability.startTracking { [weak self] status in
            self?.networkBecameReachable(status)
        }
        startHandler = completionHandler
        scheduleStartTimeout()
        vpnAdapter.connect(using: packetFlow)
        os_log("OpenVPNAdapter connect started", log: Self.vpnLog, type: .info)
        fileLog("OpenVPNAdapter connect started key-direction=1 disableClientCert sslDebug=0")
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
        sawConnecting = false
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

    /// VPN Gate / SoftEther profile tweaks that the adapter flags cannot
    /// express on their own: drop the dummy client cert, force tls-auth
    /// key-direction 1, and remove tls-version-min / tls-cipher lines that
    /// override `forceCiphersuitesAESCBC` on the mbed TLS build.
    private static func softEtherProfile(_ data: Data) -> Data {
        guard var text = String(data: data, encoding: .utf8) else { return data }
        text = stripBlock(text, tag: "cert")
        text = stripBlock(text, tag: "key")
        text = stripBlock(text, tag: "pkcs12")
        let drop = [
            #"(?m)^\s*tls-version-min\b.*\n?"#,
            #"(?m)^\s*tls-cipher\b.*\n?"#,
            #"(?m)^\s*tls-ciphersuites\b.*\n?"#,
        ]
        for pattern in drop {
            text = text.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        if text.range(of: #"(?m)^\s*key-direction\b"#, options: .regularExpression) != nil {
            text = text.replacingOccurrences(
                of: #"(?m)^\s*key-direction\s+\S+"#,
                with: "key-direction 1",
                options: .regularExpression
            )
        } else {
            text += "\nkey-direction 1\n"
        }
        if text.range(of: #"(?m)^\s*verb\b"#, options: .regularExpression) != nil {
            text = text.replacingOccurrences(
                of: #"(?m)^\s*verb\s+\S+"#,
                with: "verb 1",
                options: .regularExpression
            )
        } else {
            text += "\nverb 1\n"
        }
        return Data(text.utf8)
    }

    private static func stripBlock(_ text: String, tag: String) -> String {
        text.replacingOccurrences(
            of: "(?s)<\(tag)>.*?</\(tag)>\\s*",
            with: "",
            options: .regularExpression
        )
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
        let settings = Self.prepareTunnelSettings(networkSettings)
        setTunnelNetworkSettings(settings) { error in
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
        retainedLogLines += 1
        let keep = retainedLogLines <= 24
            || logMessage.contains("VERIFY")
            || logMessage.contains("ERROR")
            || logMessage.contains("AUTH")
            || logMessage.contains("PUSH")
            || logMessage.contains("fatal")
        if keep {
            os_log("%{public}@", log: Self.vpnLog, type: .info, logMessage)
            fileLog(logMessage)
        }
    }
}

extension PacketTunnelProvider {
    /// Settings iOS 16 will actually install.
    ///
    /// iPadOS 16 rejects a packet tunnel when the MTU is missing or above
    /// ~1400, when IPv6 addresses and prefix lengths disagree, or when DNS
    /// match-domains are set with an empty server list. iOS 27 accepts
    /// those and the same binary then looks like an iPad-only failure.
    static func prepareTunnelSettings(
        _ settings: NEPacketTunnelNetworkSettings?
    ) -> NEPacketTunnelNetworkSettings? {
        guard let settings else { return nil }
        if let ipv6 = settings.ipv6Settings {
            let addresses = ipv6.addresses
            let prefixes = ipv6.networkPrefixLengths
            if addresses.isEmpty || prefixes.count != addresses.count {
                settings.ipv6Settings = nil
            }
        }
        if #unavailable(iOS 17.0) {
            let mtu = settings.mtu?.intValue ?? 0
            if mtu < 1280 || mtu > 1400 {
                settings.mtu = NSNumber(value: 1280)
            }
        }
        if let dns = settings.dnsSettings, !dns.servers.isEmpty {
            dns.matchDomains = [""]
        } else {
            settings.dnsSettings = nil
        }
        return settings
    }
}
