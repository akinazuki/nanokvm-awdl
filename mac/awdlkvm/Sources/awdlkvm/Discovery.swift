import Darwin
import Foundation
import Network
import dnssd

final class AWDLDiscovery: @unchecked Sendable {
    private let type: String
    private let wantName: String?
    private let onResolved: @Sendable (NWEndpoint, String) -> Void
    private let fixedInterface: UInt32
    private let queue = DispatchQueue(label: "awdlkvm.discovery")
    private var browseRef: DNSServiceRef?
    private var resolveRef: DNSServiceRef?
    private var addrRef: DNSServiceRef?
    private var resolvedPort: UInt16 = 0
    private var interfaceIndex: UInt32 = 0
    private var delivered = false

    init(type: String, name: String?, interface: UInt32, onResolved: @escaping @Sendable (NWEndpoint, String) -> Void) {
        self.type = type
        self.wantName = name
        self.fixedInterface = interface
        self.onResolved = onResolved
    }

    func start() throws {
        var ref: DNSServiceRef?
        let context = Unmanaged.passUnretained(self).toOpaque()
        let flags = DNSServiceFlags(kDNSServiceFlagsIncludeAWDL)
        let err = DNSServiceBrowse(&ref, flags, fixedInterface, type, "local.", browseCallback, context)
        guard err == kDNSServiceErr_NoError, let ref else {
            throw NSError(domain: "awdlkvm", code: Int(err), userInfo: [NSLocalizedDescriptionKey: "DNSServiceBrowse failed (\(err))"])
        }
        browseRef = ref
        DNSServiceSetDispatchQueue(ref, queue)
    }

    fileprivate func onBrowse(name: String, regtype: String, domain: String, interface: UInt32) {
        if delivered { return }
        if let wantName, name.caseInsensitiveCompare(wantName) != .orderedSame { return }
        delivered = true
        interfaceIndex = interface
        var ifname = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        let scope = if_indextoname(interface, &ifname).map { String(cString: $0) } ?? "awdl0"
        let endpoint = NWEndpoint.service(name: name, type: regtype, domain: domain, interface: nil)
        [browseRef, resolveRef, addrRef].forEach { $0.map { DNSServiceRefDeallocate($0) } }
        browseRef = nil; resolveRef = nil; addrRef = nil
        onResolved(endpoint, scope)
    }

    fileprivate func onResolve(host: String, port: UInt16, interface: UInt32) {
        if delivered { return }
        resolvedPort = port
        interfaceIndex = interface
        addrRef.map { DNSServiceRefDeallocate($0) }
        addrRef = nil
        var ref: DNSServiceRef?
        let context = Unmanaged.passUnretained(self).toOpaque()
        let flags = DNSServiceFlags(kDNSServiceFlagsIncludeAWDL)
        let err = DNSServiceGetAddrInfo(
            &ref, flags, interface, DNSServiceProtocol(kDNSServiceProtocol_IPv6), host, addrInfoCallback, context)
        if err == kDNSServiceErr_NoError, let ref {
            addrRef = ref
            DNSServiceSetDispatchQueue(ref, queue)
        }
    }

    fileprivate func onAddress(_ ip: String, interface: UInt32) {
        if delivered { return }
        delivered = true
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        let scope = if_indextoname(interface, &name).map { String(cString: $0) } ?? "awdl0"
        let host = ip.hasPrefix("fe80") ? "\(ip)%\(scope)" : ip
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: resolvedPort)!)
        [browseRef, resolveRef, addrRef].forEach { $0.map { DNSServiceRefDeallocate($0) } }
        browseRef = nil; resolveRef = nil; addrRef = nil
        onResolved(endpoint, scope)
    }
}

private func browseCallback(
    _ ref: DNSServiceRef?, _ flags: DNSServiceFlags, _ interface: UInt32, _ error: DNSServiceErrorType,
    _ name: UnsafePointer<CChar>?, _ regtype: UnsafePointer<CChar>?, _ domain: UnsafePointer<CChar>?,
    _ context: UnsafeMutableRawPointer?
) {
    guard error == kDNSServiceErr_NoError, flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0,
        let context, let name, let regtype, let domain
    else { return }
    let discovery = Unmanaged<AWDLDiscovery>.fromOpaque(context).takeUnretainedValue()
    discovery.onBrowse(
        name: String(cString: name), regtype: String(cString: regtype),
        domain: String(cString: domain), interface: interface)
}

private func resolveCallback(
    _ ref: DNSServiceRef?, _ flags: DNSServiceFlags, _ interface: UInt32, _ error: DNSServiceErrorType,
    _ fullname: UnsafePointer<CChar>?, _ host: UnsafePointer<CChar>?, _ port: UInt16,
    _ txtLen: UInt16, _ txt: UnsafePointer<UInt8>?, _ context: UnsafeMutableRawPointer?
) {
    guard error == kDNSServiceErr_NoError, let context, let host else { return }
    let discovery = Unmanaged<AWDLDiscovery>.fromOpaque(context).takeUnretainedValue()
    discovery.onResolve(host: String(cString: host), port: port.bigEndian, interface: interface)
}

private func addrInfoCallback(
    _ ref: DNSServiceRef?, _ flags: DNSServiceFlags, _ interface: UInt32, _ error: DNSServiceErrorType,
    _ hostname: UnsafePointer<CChar>?, _ address: UnsafePointer<sockaddr>?, _ ttl: UInt32,
    _ context: UnsafeMutableRawPointer?
) {
    guard error == kDNSServiceErr_NoError, flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0,
        let context, let address, address.pointee.sa_family == sa_family_t(AF_INET6)
    else { return }
    var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
    let ip = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 -> String? in
        var addr = sin6.pointee.sin6_addr
        return inet_ntop(AF_INET6, &addr, &text, socklen_t(text.count)).map { String(cString: $0) }
    }
    guard let ip else { return }
    let discovery = Unmanaged<AWDLDiscovery>.fromOpaque(context).takeUnretainedValue()
    discovery.onAddress(ip, interface: interface)
}

final class AWDLListing: @unchecked Sendable {
    private let type: String
    private let interface: UInt32
    private let onName: @Sendable (String) -> Void
    private let queue = DispatchQueue(label: "awdlkvm.listing")
    private var ref: DNSServiceRef?

    init(type: String, interface: UInt32, onName: @escaping @Sendable (String) -> Void) {
        self.type = type
        self.interface = interface
        self.onName = onName
    }

    func start() throws {
        var r: DNSServiceRef?
        let context = Unmanaged.passUnretained(self).toOpaque()
        let flags = DNSServiceFlags(kDNSServiceFlagsIncludeAWDL)
        let err = DNSServiceBrowse(&r, flags, interface, type, "local.", listingCallback, context)
        guard err == kDNSServiceErr_NoError, let r else {
            throw NSError(domain: "awdlkvm", code: Int(err))
        }
        ref = r
        DNSServiceSetDispatchQueue(r, queue)
    }

    fileprivate func report(_ name: String) { onName(name) }
}

private func listingCallback(
    _ ref: DNSServiceRef?, _ flags: DNSServiceFlags, _ interface: UInt32, _ error: DNSServiceErrorType,
    _ name: UnsafePointer<CChar>?, _ regtype: UnsafePointer<CChar>?, _ domain: UnsafePointer<CChar>?,
    _ context: UnsafeMutableRawPointer?
) {
    guard error == kDNSServiceErr_NoError, flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0,
        let context, let name
    else { return }
    Unmanaged<AWDLListing>.fromOpaque(context).takeUnretainedValue().report(String(cString: name))
}
