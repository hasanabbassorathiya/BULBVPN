import Darwin
import Foundation
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
    private var running = false

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
            if code != 0 {
                code = self.connect(host: host, sni: sni, plain: true)
            }
            if code != 0 {
                completion(self.failure("softether connect \(code)"))
                return
            }
            guard let client = self.client else {
                completion(self.failure("softether missing client"))
                return
            }
            // DHCP Ack lands on the library's data thread after connect
            // returns. The address stays 0 until that Ack.
            var ip: UInt32 = 0
            let dhcpDeadline = Date().addingTimeInterval(12)
            while Date() < dhcpDeadline {
                ip = softether_get_assigned_ip(client)
                if ip != 0 { break }
                Thread.sleep(forTimeInterval: 0.25)
            }
            let mask = softether_get_assigned_mask(client)
            let gateway = softether_get_gateway_ip(client)
            if ip == 0 {
                completion(self.failure("softether no address"))
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
                    completion(error)
                    return
                }
                self.running = true
                self.startPacketPump()
                completion(nil)
            }
        }
    }

    func stop() {
        running = false
        if let client {
            softether_request_stop(client)
            softether_disconnect(client)
            softether_destroy(client)
        }
        client = nil
        if uploadFd >= 0 { close(uploadFd) }
        if downloadFd >= 0 { close(downloadFd) }
        uploadFd = -1
        downloadFd = -1
        if SoftEtherSession.current === self {
            SoftEtherSession.current = nil
        }
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
        client = created
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
        if plain {
            softether_set_plain_password(created)
        }
        let code = softether_connect(created)
        if code != 0 {
            softether_destroy(created)
            client = nil
            return code
        }
        return 0
    }

    private func installTunnelFds(_ client: softether_client_t) {
        guard let upload = Self.socketPair(SOCK_DGRAM),
              let download = Self.socketPair(SOCK_DGRAM) else {
            return
        }
        var size: Int32 = 1024 * 1024
        let len = socklen_t(MemoryLayout<Int32>.size)
        for fd in [upload.0, upload.1, download.0, download.1] {
            setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, len)
            setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &size, len)
        }
        // Library reads upload[0] and writes download[0].
        softether_set_tunnel_fds(client, download.0, upload.0)
        uploadFd = upload.1
        downloadFd = download.1
    }

    private func startPacketPump() {
        guard let flow = provider?.packetFlow, downloadFd >= 0, uploadFd >= 0 else {
            return
        }
        let download = downloadFd
        let upload = uploadFd
        packetPump = Thread {
            var buffer = [UInt8](repeating: 0, count: 2048)
            while self.running {
                var waited = pollfd(fd: download, events: Int16(POLLIN), revents: 0)
                if poll(&waited, 1, 200) <= 0 { continue }
                let count = recv(download, &buffer, buffer.count, 0)
                if count <= 0 { continue }
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
                packet.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    _ = send(upload, base, packet.count, 0)
                }
            }
            self.readPackets(flow: flow, upload: upload)
        }
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
