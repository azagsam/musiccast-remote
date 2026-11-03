import Darwin
import Foundation

struct DiscoveredReceiver: Identifiable, Hashable {
    let host: String
    let name: String
    let model: String?
    let deviceID: String?

    var id: String { host }
}

/// Finds MusicCast receivers: SSDP for candidates, then YXC to confirm each one.
enum Discovery {
    static func find(timeout: TimeInterval = 3) async -> [DiscoveredReceiver] {
        let hosts = await ssdpHosts(timeout: timeout)
        return await withTaskGroup(of: DiscoveredReceiver?.self) { group in
            for host in hosts {
                group.addTask { await identify(host) }
            }
            var found: [DiscoveredReceiver] = []
            for await receiver in group {
                if let receiver { found.append(receiver) }
            }
            return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// Anything that doesn't answer the Yamaha API isn't a receiver.
    private static func identify(_ host: String) async -> DiscoveredReceiver? {
        let client = Client(host: host)
        guard let network: NetworkStatus = try? await client.get("system/getNetworkStatus") else { return nil }
        let info: DeviceInfo? = try? await client.get("system/getDeviceInfo")
        return DiscoveredReceiver(host: host, name: network.network_name, model: info?.model_name, deviceID: info?.device_id)
    }

    private static func ssdpHosts(timeout: TimeInterval) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: search(timeout: timeout))
            }
        }
    }

    /// MusicCast devices are UPnP media renderers, so they answer this M-SEARCH.
    private static func search(timeout: TimeInterval) -> [String] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var ttl: UInt8 = 2
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        var wait = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))

        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = in_port_t(1900).bigEndian
        target.sin_addr.s_addr = inet_addr("239.255.255.250")

        let message = [
            "M-SEARCH * HTTP/1.1",
            "HOST: 239.255.255.250:1900",
            "MAN: \"ssdp:discover\"",
            "MX: 2",
            "ST: urn:schemas-upnp-org:device:MediaRenderer:1",
            "", "",
        ].joined(separator: "\r\n")
        let bytes = Array(message.utf8)

        // UDP can drop the request, so send it twice.
        for _ in 0..<2 {
            _ = withUnsafePointer(to: &target) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        var hosts: [String] = []
        var buffer = [UInt8](repeating: 0, count: 2048)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var sender = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &sender) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buffer, buffer.count, 0, $0, &length)
                }
            }
            guard count > 0 else { continue }
            let host = String(cString: inet_ntoa(sender.sin_addr))
            if !hosts.contains(host) { hosts.append(host) }
        }
        return hosts
    }
}
