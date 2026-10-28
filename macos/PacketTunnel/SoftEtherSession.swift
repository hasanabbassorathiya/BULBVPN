import Darwin
import Foundation
import Network
import NetworkExtension
import os.log

private let softEtherLog = OSLog(
    subsystem: "app.bulbvpn.com",
    category: "SoftEther"
)

@_cdecl("bulb_softether_dial")
func bulbSoftetherDial(
    _ host: UnsafePointer<CChar>?,
    _ port: UInt16
) -> Int32 {
    guard let host else { return -1 }
    return SoftEtherSession.current?.dial(
        host: String(cString: host),
        port: port
    ) ?? -1
}

@_cdecl("bulb_softether_log")
func bulbSoftetherLog(_ level: Int32, _ message: UnsafePointer<CChar>?) {
    guard let message else { return }
    let text = String(cString: message)
    os_log("%{public}@", log: softEtherLog, type: .info, text)
    softether_free_log_text(message)
    _ = level
    let line = "\(ISO8601DateFormatter().string(from: Date())) se \(text)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let dir = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.com.bulbvpn.app"
    ) {
        let file = dir.appendingPathComponent("Library/Caches/bulb-tunnel.log")
        if FileManager.default.fileExists(atPath: file.path),
           let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: file)
        }
    }
}

/// SoftEther SSL-VPN inside the packet tunnel.
///
/// VPN Gate's OpenVPN listener accepts the certificate and then never
/// finishes. This is the same client Android uses: hub VPNGATE, vpn/vpn,
/// TCP 443, SNI `{host}.opengw.net`.
final class SoftEtherSession {
    static weak var current: SoftEtherSession?

    private weak var provider: NEPacketTunnelProvider?
    private var client: softether_client_t?
    private var bridges: [TcpBridge] = []
    private var uploadFd: Int32 = -1
    private var downloadFd: Int32 = -1
    private var packetPump: Thread?
    private var pathMonitor: NWPathMonitor?
    private var pathSignature = ""

    /// Cumulative session traffic for the app's DOWN gauge. The extension is
    /// the only process that sees the SoftEther packets, so these counters
    /// travel back over the OPENVPN_STATS provider message.
    private let statsLock = NSLock()
    private var bytesIn: Int64 = 0
    private var bytesOut: Int64 = 0

    func statistics() -> (down: Int64, up: Int64) {
        statsLock.lock()
        defer { statsLock.unlock() }
        return (bytesIn, bytesOut)
    }

    private func addIncoming(_ count: Int) {
        guard count > 0 else { return }
        statsLock.lock()
        bytesIn += Int64(count)
        statsLock.unlock()
    }

    private func addOutgoing(_ count: Int) {
        guard count > 0 else { return }
        statsLock.lock()
        bytesOut += Int64(count)
        statsLock.unlock()
    }

    /// `softether_destroy` while another thread is inside the client (health
    /// probe, DHCP wait, packet pump) aborts the extension. Every handle access
    /// is serialised here, and a destroy is deferred while a connect is still
    /// on the stack.
    private let stateLock = NSLock()
    private var _running = false
    private var connecting = false
    private var cancelled = false

    private var running: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _running
    }

    private func markRunning() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        if cancelled { return false }
        _running = true
        connecting = false
        return true
    }

    private var isCancelled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancelled
    }

    private func currentClient() -> softether_client_t? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return client
    }

    init(provider: NEPacketTunnelProvider) {
        self.provider = provider
    }

    func start(host: String, sni: String, completion: @escaping (Error?) -> Void) {
        SoftEtherSession.current = self
        softether_set_log_callback(bulbSoftetherLog)
        softether_set_tcp_dial_callback(bulbSoftetherDial)
        softether_set_bind_interface(carrierInterface())

        Thread.detachNewThread { [self] in
            var code = self.connect(host: host, sni: sni, plain: false)
            // Only an authentication rejection (-5, SOFTETHER_ERR_AUTH_FAILED)
            // is worth retrying with the plain password. Retrying on a
            // timeout / connection failure doubles the wait on a dead or
            // filtered relay and is why a selected country could sit on
            // "connecting" for over a minute.
            let authFailed: Int32 = -5
            if code == authFailed {
                code = self.connect(host: host, sni: sni, plain: true)
            }
            if code != 0 {
                self.failStart("softether connect \(code)", completion: completion)
                return
            }
            guard let client = self.currentClient() else {
                self.failStart("softether missing client", completion: completion)
                return
            }
            // DHCP Ack lands on the library's data thread after connect
            // returns. The address stays 0 until that Ack.
            var ip: UInt32 = 0
            let dhcpDeadline = Date().addingTimeInterval(12)
            while Date() < dhcpDeadline && !self.isCancelled {
                ip = softether_get_assigned_ip(client)
                if ip != 0 { break }
                Thread.sleep(forTimeInterval: 0.25)
            }
            let mask = softether_get_assigned_mask(client)
            let gateway = softether_get_gateway_ip(client)
            if ip == 0 {
                self.failStart("softether no address", completion: completion)
                return
            }
            let settings = self.tunnelSettings(
                server: host,
                address: Self.format(ip),
                mask: Self.format(mask == 0 ? 0xFFFF0000 : mask),
                dns: gateway == 0 ? "1.1.1.1" : Self.format(gateway)
            )
            self.provider?.setTunnelNetworkSettings(settings) { error in
                if let error {
                    self.failStart(
                        "tunnel settings \(error.localizedDescription)",
                        completion: completion
                    )
                    return
                }
                if !self.markRunning() {
                    self.failStart("cancelled", completion: completion)
                    return
                }
                self.startPacketPump()
                self.startHealthMonitor()
                self.startPathMonitor()
                completion(nil)
            }
        }
    }

    /// The tunnel extension is the only process that can prove the SSL session
    /// is still alive. If the library reports three consecutive misses, fail
    /// the tunnel so the app can re-dial instead of showing a false "Connected".
    private func startHealthMonitor() {
        Thread.detachNewThread { [weak self] in
            guard let self else { return }
            Thread.sleep(forTimeInterval: 10)
            var misses = 0
            while self.running {
                Thread.sleep(forTimeInterval: 5)
                if !self.running { return }
                self.stateLock.lock()
                let client = self.client
                let alive = client.map { softether_is_connected($0) } ?? false
                self.stateLock.unlock()
                if alive {
                    misses = 0
                } else {
                    misses += 1
                    if misses >= 3 {
                        self.stateLock.lock()
                        self._running = false
                        self.stateLock.unlock()
                        self.provider?.cancelTunnelWithError(
                            NSError(
                                domain: "SoftEther",
                                code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "softether link lost"]
                            )
                        )
                        return
                    }
                }
            }
        }
    }

    /// The control connection is bound to the carrier interface it was dialled
    /// from. Wi-Fi to cellular (or the reverse) leaves it on an address that no
    /// longer routes; the library then reports dead while the OS still says
    /// the tunnel is up. Fail the tunnel instead so the app re-dials on the
    /// new network.
    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePath(path)
        }
        pathMonitor = monitor
        monitor.start(queue: DispatchQueue(label: "app.bulbvpn.com.softether.path"))
    }

    private func handlePath(_ path: Network.NWPath) {
        guard running else { return }
        // Inside the extension the path can list the tunnel itself. Only the
        // physical interfaces identify the carrier network.
        let physical = path.availableInterfaces.filter {
            !Self.isTunnelInterface($0.name)
        }
        // Wi-Fi and cellular can both be available while only one is in use.
        // A switch between them must count as a change even when the set of
        // interfaces stayed the same.
        let active = physical.filter { interface in
            switch interface.type {
            case .wifi: return path.usesInterfaceType(.wifi)
            case .cellular: return path.usesInterfaceType(.cellular)
            case .wiredEthernet: return path.usesInterfaceType(.wiredEthernet)
            default: return false
            }
        }
        let chosen = active.isEmpty ? physical : active
        let signature = chosen
            .map { $0.name }
            .sorted()
            .joined(separator: ",")
        guard !signature.isEmpty else { return }
        stateLock.lock()
        if pathSignature.isEmpty {
            pathSignature = signature
            stateLock.unlock()
            return
        }
        let changed = pathSignature != signature
        stateLock.unlock()
        guard changed else { return }
        os_log(
            "network changed: %{public}@",
            log: softEtherLog,
            type: .default,
            signature
        )
        stateLock.lock()
        let wasRunning = _running
        _running = false
        stateLock.unlock()
        guard wasRunning else { return }
        provider?.cancelTunnelWithError(
            NSError(
                domain: "SoftEther",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "network changed"]
            )
        )
    }

    private static func isTunnelInterface(_ name: String) -> Bool {
        if name == "lo0" { return true }
        return ["utun", "ipsec", "ppp", "tap"].contains { name.hasPrefix($0) }
    }

    func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        stateLock.lock()
        _running = false
        cancelled = true
        let handle = client
        let inFlight = connecting
        if !inFlight {
            client = nil
        }
        let up = uploadFd
        let down = downloadFd
        uploadFd = -1
        downloadFd = -1
        stateLock.unlock()
        if let handle {
            // Tearing a client down while softether_connect is still inside it
            // is the crash this lock exists to prevent. Ask it to return and
            // let the connect thread destroy its own handle.
            softether_request_stop(handle)
            if !inFlight {
                softether_disconnect(handle)
                softether_destroy(handle)
            }
        }
        // Let the packet pump leave poll()/recv() before the fds are reused.
        Thread.sleep(forTimeInterval: 0.2)
        if up >= 0 { close(up) }
        if down >= 0 { close(down) }
        if SoftEtherSession.current === self {
            SoftEtherSession.current = nil
        }
    }

    private func failStart(
        _ message: String,
        completion: @escaping (Error?) -> Void
    ) {
        stateLock.lock()
        let handle = client
        client = nil
        connecting = false
        let up = uploadFd
        let down = downloadFd
        uploadFd = -1
        downloadFd = -1
        stateLock.unlock()
        if let handle {
            softether_request_stop(handle)
            softether_disconnect(handle)
            softether_destroy(handle)
        }
        if up >= 0 { close(up) }
        if down >= 0 { close(down) }
        completion(failure(message))
    }

    func dial(host: String, port: UInt16) -> Int32 {
        guard let provider else { return -1 }
        guard let pair = Self.socketPair(SOCK_STREAM) else { return -1 }
        let libraryEnd = pair.0
        let appEnd = pair.1
        var one: Int32 = 1
        setsockopt(libraryEnd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(appEnd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        let endpoint = NWHostEndpoint(hostname: host, port: String(port))
        let connection: NWTCPConnection? = DispatchQueue.main.sync {
            provider.createTCPConnection(
                to: endpoint,
                enableTLS: false,
                tlsParameters: nil,
                delegate: nil
            )
        }
        guard let connection else {
            close(libraryEnd)
            close(appEnd)
            return -1
        }
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            let state = DispatchQueue.main.sync { connection.state }
            if state == .connected { break }
            if state == .cancelled || state == .disconnected {
                close(libraryEnd)
                close(appEnd)
                return -1
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if DispatchQueue.main.sync(execute: { connection.state }) != .connected {
            close(libraryEnd)
            close(appEnd)
            return -1
        }
        let bridge = TcpBridge(fd: appEnd, connection: connection)
        bridges.append(bridge)
        bridge.start()
        return libraryEnd
    }

    private func connect(host: String, sni: String, plain: Bool) -> Int32 {
        guard let created = softether_create(host, 443, "VPNGATE", "vpn", "vpn") else {
            return -99
        }
        stateLock.lock()
        if cancelled {
            stateLock.unlock()
            softether_destroy(created)
            return -2
        }
        client = created
        connecting = true
        stateLock.unlock()
        softether_set_verify_certificate(created, false)
        softether_set_hostname(created, sni)
        // Network Extension owns the utun. Both Apple builds use the fd
        // adapter and socketpairs; the library must not install routes.
        softether_set_default_route(created, false)
        installTunnelFds(created)
        softether_set_reconnect(created, false, 0)
        softether_set_max_connections(created, 1)
        softether_set_udp_acceleration(created, false)
        softether_set_ip_version(created, 4)
        softether_set_connect_timeout(created, 20000)
        // Keep the carrier NAT mapping alive and surface a black-holed session
        // instead of leaving the UI on "Connected" forever.
        softether_set_keepalive_interval(created, 15000)
        softether_set_read_timeout(created, 30000)
        if plain {
            softether_set_plain_password(created)
        }
        let code = softether_connect(created)
        stateLock.lock()
        let aborted = cancelled
        if code != 0 || aborted {
            // Keep `connecting` true through DHCP/settings on success so a
            // user stop cannot destroy the handle under the start thread.
            connecting = false
            if client == created {
                client = nil
            }
        }
        stateLock.unlock()
        if code != 0 || aborted {
            softether_request_stop(created)
            softether_disconnect(created)
            softether_destroy(created)
            // The socketpair ends installed for this attempt belong to this
            // attempt. Without closing them every retry leaks four fds and a
            // long-lived extension eventually runs out.
            closeTunnelFds()
            return code != 0 ? code : -2
        }
        return 0
    }

    /// Closes the app-side ends of the two tunnel socketpairs. Only safe while
    /// no packet pump is running (before the tunnel is marked running).
    private func closeTunnelFds() {
        stateLock.lock()
        let up = uploadFd
        let down = downloadFd
        uploadFd = -1
        downloadFd = -1
        stateLock.unlock()
        if up >= 0 { close(up) }
        if down >= 0 { close(down) }
    }

    private func installTunnelFds(_ client: softether_client_t) {
        guard let upload = Self.socketPair(SOCK_DGRAM) else {
            return
        }
        guard let download = Self.socketPair(SOCK_DGRAM) else {
            close(upload.0)
            close(upload.1)
            return
        }
        var size: Int32 = 1024 * 1024
        let len = socklen_t(MemoryLayout<Int32>.size)
        for fd in [upload.0, upload.1, download.0, download.1] {
            setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, len)
            setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &size, len)
        }
        stateLock.lock()
        if cancelled {
            stateLock.unlock()
            for fd in [upload.0, upload.1, download.0, download.1] { close(fd) }
            return
        }
        // Library reads upload[0] and writes download[0].
        softether_set_tunnel_fds(client, download.0, upload.0)
        uploadFd = upload.1
        downloadFd = download.1
        stateLock.unlock()
    }

    private func startPacketPump() {
        stateLock.lock()
        let download = downloadFd
        let upload = uploadFd
        stateLock.unlock()
        guard let flow = provider?.packetFlow, download >= 0, upload >= 0 else {
            return
        }
        packetPump = Thread {
            var buffer = [UInt8](repeating: 0, count: 2048)
            while self.running {
                var waited = pollfd(fd: download, events: Int16(POLLIN), revents: 0)
                if poll(&waited, 1, 200) <= 0 { continue }
                let count = recv(download, &buffer, buffer.count, 0)
                if count <= 0 { continue }
                self.addIncoming(count)
                let packet = Data(buffer[0..<count])
                flow.writePackets([packet], withProtocols: [NSNumber(value: AF_INET)])
            }
        }
        packetPump?.name = "softether-dl"
        packetPump?.start()
        readPackets(flow: flow, upload: upload)
    }

    private func readPackets(flow: NEPacketTunnelFlow, upload: Int32) {
        flow.readPackets { [weak self] packets, _ in
            guard let self, self.running else { return }
            for packet in packets {
                guard Self.isIPv4(packet) else { continue }
                packet.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    let sent = send(upload, base, packet.count, 0)
                    self.addOutgoing(Int(sent))
                }
            }
            self.readPackets(flow: flow, upload: upload)
        }
    }

    /// The SoftEther library is IPv4-only. The IPv6 settings below exist so
    /// the carrier's IPv6 traffic enters the tunnel instead of escaping around
    /// it; forwarding those packets to an IPv4 session would corrupt it, so
    /// they are dropped here.
    private static func isIPv4(_ packet: Data) -> Bool {
        guard let first = packet.first else { return false }
        return first >> 4 == 4
    }

    private func tunnelSettings(
        server: String,
        address: String,
        mask: String,
        dns: String
    ) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: server)
        let ipv4 = NEIPv4Settings(addresses: [address], subnetMasks: [mask])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        // Capture IPv6 even though this tunnel cannot carry it. Without a
        // route here a dual-stack carrier sends IPv6 outside the tunnel and
        // every site, Google included, sees the real country.
        let ipv6 = NEIPv6Settings(
            addresses: ["fd00:6275:6c62::1"],
            networkPrefixLengths: [64]
        )
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6
        settings.mtu = 1280
        let dnsSettings = NEDNSSettings(servers: [dns, "1.1.1.1"])
        dnsSettings.matchDomains = [""]
        settings.dnsSettings = dnsSettings
        return settings
    }

    private func failure(_ message: String) -> NSError {
        os_log("%{public}@", log: softEtherLog, type: .error, message)
        return NSError(
            domain: "SoftEther",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private static func socketPair(_ type: Int32) -> (Int32, Int32)? {
        var ends = [Int32](repeating: -1, count: 2)
        let result = ends.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return socketpair(AF_UNIX, type, 0, base)
        }
        guard result == 0 else { return nil }
        return (ends[0], ends[1])
    }

    private static func format(_ value: UInt32) -> String {
        let a = (value >> 24) & 0xFF
        let b = (value >> 16) & 0xFF
        let c = (value >> 8) & 0xFF
        let d = value & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }
}

private final class TcpBridge {
    let fd: Int32
    let connection: NWTCPConnection

    init(fd: Int32, connection: NWTCPConnection) {
        self.fd = fd
        self.connection = connection
    }

    func start() {
        Thread.detachNewThread { [self] in
            var buffer = [UInt8](repeating: 0, count: 16384)
            while true {
                let count = read(fd, &buffer, buffer.count)
                if count <= 0 { break }
                let data = Data(buffer[0..<count])
                let gate = DispatchSemaphore(value: 0)
                connection.write(data) { _ in gate.signal() }
                gate.wait()
            }
        }
        pumpFromConnection()
    }

    private func pumpFromConnection() {
        connection.readMinimumLength(1, maximumLength: 16384) { [weak self] data, error in
            guard let self, error == nil, let data, !data.isEmpty else { return }
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                _ = write(self.fd, base, data.count)
            }
            self.pumpFromConnection()
        }
    }
}

private func carrierInterface() -> String {
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let first = head else { return "en0" }
    defer { freeifaddrs(head) }
    var wifi: String?
    var cell: String?
    var cursor: UnsafeMutablePointer<ifaddrs>? = first
    while let item = cursor {
        let name = String(cString: item.pointee.ifa_name)
        if let address = item.pointee.ifa_addr,
           address.pointee.sa_family == UInt8(AF_INET) {
            if name.hasPrefix("en") { wifi = name }
            if name.hasPrefix("pdp_ip") { cell = name }
        }
        cursor = item.pointee.ifa_next
    }
    return wifi ?? cell ?? "en0"
}
