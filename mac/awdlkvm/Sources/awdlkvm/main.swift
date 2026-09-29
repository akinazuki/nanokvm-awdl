import ArgumentParser
import Foundation
import Network

struct Options {
    var localPort: UInt16 = 8443
    var serviceType = "_nanokvm._tcp"
    var name: String?
    var browseSeconds: Double = 15
    var interface = "awdl0"
    var list = false
    var host: String?
    var mac: String?
}

struct AwdlKVM: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "awdlkvm",
        abstract: "Reach a NanoKVM over AWDL (no Wi-Fi pairing).",
        discussion: """
            Discovers _nanokvm._tcp peers over AWDL and proxies https://localhost:<port> \
            to the KVM's web UI.
            """
    )

    @Option(name: [.short, .long], help: "Local HTTPS port.")
    var port: UInt16 = 8443
    @Option(name: [.short, .long], help: "Connect to the KVM with this advertised name.")
    var name: String?
    @Flag(name: [.short, .long], help: "List nearby NanoKVMs and exit.")
    var list = false
    @Option(name: [.short, .long], help: "Interface to use (awdl0, or 'any' for all).")
    var interface: String = "awdl0"
    @Option(help: "Bonjour service type.")
    var type: String = "_nanokvm._tcp"
    @Option(help: "Discovery timeout, in seconds.")
    var timeout: Double = 15
    @Option(help: "Fallback: connect to this address (a%scope:port).")
    var host: String?
    @Option(name: [.short, .long], help: "Fallback: derive the awdl0 address from the KVM Wi-Fi MAC.")
    var mac: String?

    func options() -> Options {
        Options(
            localPort: port, serviceType: type, name: name, browseSeconds: timeout,
            interface: interface, list: list, host: host, mac: mac)
    }
}

let options = AwdlKVM.parseOrExit().options()

final class Proxy: @unchecked Sendable {
    private let a: NWConnection
    private let b: NWConnection
    private var closed = false
    private let lock = NSLock()
    private var keepAlive: Proxy?

    init(_ a: NWConnection, _ b: NWConnection) {
        self.a = a
        self.b = b
    }

    func run() {
        keepAlive = self
        pump(from: a, to: b)
        pump(from: b, to: a)
    }

    private func pump(from src: NWConnection, to dst: NWConnection) {
        src.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                dst.send(content: data, completion: .contentProcessed { sendError in
                    if sendError != nil {
                        self.shutdown()
                    } else {
                        self.pump(from: src, to: dst)
                    }
                })
            } else if isComplete || error != nil {
                self.shutdown()
            } else {
                self.pump(from: src, to: dst)
            }
        }
    }

    private func shutdown() {
        lock.lock()
        let already = closed
        closed = true
        lock.unlock()
        guard !already else { return }
        a.cancel()
        b.cancel()
        keepAlive = nil
    }
}

final class Bridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "awdlkvm")
    private let peerParams: NWParameters
    private var endpoint: NWEndpoint?
    private var discovery: AWDLDiscovery?
    private var listener: NWListener?
    private var listening = false
    private let lock = NSLock()

    init() {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        peerParams = params
    }

    private var cacheName: String { options.name ?? "default" }

    private var listed = Set<String>()
    private var listingKeepalive: AWDLListing?

    func start() {
        if options.list {
            print("NanoKVM devices over \(options.interface) (5 s)…")
            let ifIndex: UInt32 = options.interface == "any" ? 0 : if_nametoindex(options.interface)
            let d = AWDLListing(type: options.serviceType, interface: ifIndex) { name in
                if self.listed.insert(name).inserted { print("  \(name)") }
            }
            self.discovery = nil
            try? d.start()
            listingKeepalive = d
            queue.asyncAfter(deadline: .now() + 5) {
                if self.listed.isEmpty { print("  (none found)") }
                exit(0)
            }
            return
        }
        if let host = options.host, let endpoint = KVMEndpoint.fromHost(host, defaultPort: 443) {
            found(endpoint, scope: "direct")
            return
        }
        if let name = options.name {
            let endpoint = NWEndpoint.service(name: name, type: options.serviceType + ".", domain: "local.", interface: nil)
            print("Connecting to \(name) over AWDL")
            found(endpoint, scope: "named")
            return
        }
        if let mac = options.mac, let endpoint = KVMEndpoint.fromMAC(mac, scope: options.interface, port: 443) {
            print("Using \(mac) -> \(endpoint)")
            found(endpoint, scope: options.interface)
            return
        }
        if let cached = KVMEndpoint.loadCached(name: cacheName) {
            if cached.hasPrefix("svc\t") {
                let f = cached.dropFirst(4).split(separator: "\t", omittingEmptySubsequences: false)
                if f.count == 3 {
                    let endpoint = NWEndpoint.service(name: String(f[0]), type: String(f[1]), domain: String(f[2]), interface: nil)
                    print("Using remembered KVM \(f[0])")
                    found(endpoint, scope: "cached")
                    return
                }
            } else if let endpoint = KVMEndpoint.fromHost(cached, defaultPort: 443) {
                print("Using remembered address \(cached)")
                found(endpoint, scope: "cached")
                return
            }
        }
        let ifIndex: UInt32 = options.interface == "any" ? 0 : if_nametoindex(options.interface)
        let discovery = AWDLDiscovery(type: options.serviceType, name: options.name, interface: ifIndex) { [weak self] endpoint, scope in
            self?.found(endpoint, scope: scope)
        }
        self.discovery = discovery
        do {
            try discovery.start()
            print("Looking for \(options.serviceType) over AWDL…")
        } catch {
            print("Discovery failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    private func found(_ endpoint: NWEndpoint, scope: String) {
        lock.lock()
        let already = self.endpoint != nil
        if !already { self.endpoint = endpoint }
        lock.unlock()
        guard !already else { return }
        if scope != "cached" {
            switch endpoint {
            case .service(let n, let t, let d, _):
                KVMEndpoint.saveCached(name: cacheName, host: "svc\t\(n)\t\(t)\t\(d)")
            case .hostPort(let host, let port):
                KVMEndpoint.saveCached(name: cacheName, host: "\(host):\(port.rawValue)")
            default: break
            }
        }
        startListener()
    }

    private func startListener() {
        lock.lock()
        let already = listening
        listening = true
        lock.unlock()
        guard !already else { return }
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: options.localPort)!)
            let listener = try NWListener(using: params)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] inbound in
                self?.accept(inbound)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.announceReady()
                case .failed(let error):
                    print("Listener failed: \(error)")
                    exit(1)
                default: break
                }
            }
            listener.start(queue: queue)
        } catch {
            print("Cannot listen on 127.0.0.1:\(options.localPort): \(error)")
            exit(1)
        }
    }

    private func announceReady() {
        let url = "https://localhost:\(options.localPort)/"
        lock.lock()
        let ep = endpoint
        lock.unlock()
        let label = options.name ?? ep.map(Bridge.describe) ?? "NanoKVM"
        func row(_ key: String, _ value: String) -> String {
            "  \(key):".padding(toLength: 13, withPad: " ", startingAt: 0) + value
        }
        print("")
        print("  NanoKVM ready over AWDL")
        print("")
        print(row("Local", url))
        print(row("KVM", label))
        print(row("Interface", options.interface))
        print("")
        print("  Opening in your default browser…")
        Bridge.openInBrowser(url)
    }

    private static func describe(_ ep: NWEndpoint) -> String {
        switch ep {
        case .service(let name, _, _, _): return name
        case .hostPort(let host, let port): return "\(host):\(port.rawValue)"
        default: return "\(ep)"
        }
    }

    private static func openInBrowser(_ url: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = [url]
        try? p.run()
    }

    private func accept(_ inbound: NWConnection) {
        lock.lock()
        let target = endpoint
        lock.unlock()
        guard let target else {
            inbound.cancel()
            return
        }
        let outbound = NWConnection(to: target, using: peerParams)
        PairStarter(inbound: inbound, outbound: outbound).start(on: queue)
    }
}

final class PairStarter: @unchecked Sendable {
    private let inbound: NWConnection
    private let outbound: NWConnection
    private let lock = NSLock()
    private var ready = 0
    private var finished = false
    private var keepAlive: PairStarter?

    init(inbound: NWConnection, outbound: NWConnection) {
        self.inbound = inbound
        self.outbound = outbound
    }

    func start(on queue: DispatchQueue) {
        keepAlive = self
        for connection in [inbound, outbound] {
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: self.oneReady()
                case .failed, .cancelled: self.fail()
                default: break
                }
            }
            connection.start(queue: queue)
        }
    }

    private func oneReady() {
        lock.lock()
        ready += 1
        let go = ready == 2 && !finished
        if go { finished = true }
        lock.unlock()
        if go {
            Proxy(inbound, outbound).run()
            inbound.stateUpdateHandler = nil
            outbound.stateUpdateHandler = nil
            keepAlive = nil
        }
    }

    private func fail() {
        lock.lock()
        let already = finished
        finished = true
        lock.unlock()
        guard !already else { return }
        inbound.cancel()
        outbound.cancel()
        keepAlive = nil
    }
}

let bridge = Bridge()
bridge.start()
dispatchMain()
