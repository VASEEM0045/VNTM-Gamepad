//
//  WiFiService.swift
//  VNTM Gamepad
//
//  High-performance TCP socket transport utilizing Apple's Network framework.
//  Provides Bonjour discovery (_vntmgamepad._tcp), connection state handling,
//  and active round-trip latency measurement via ping-pong packets.
//

import Foundation
import Network
import Combine
import os.log

/// Service managing Wi-Fi TCP network connections to the VNTM Gamepad companion.
///
/// Features Bonjour mDNS browsing for automatic host discovery, reliable packet
/// streaming, keep-alive heartbeats, and continuous round-trip latency tracking.
public final class WiFiService: ObservableObject {

    // MARK: - Constants

    /// Default TCP port for the VNTM Gamepad server.
    public static let defaultPort: UInt16 = 7777

    /// Bonjour service type advertised by the companion server.
    public static let bonjourServiceType = "_vntmgamepad._tcp"

    /// Ping packet magic header (ASCII: 'PING').
    private static let pingHeader: [UInt8] = [0x50, 0x49, 0x4E, 0x47]

    /// Pong packet magic header (ASCII: 'PONG').
    private static let pongHeader: [UInt8] = [0x50, 0x4F, 0x4E, 0x47]

    // MARK: - Published Properties

    /// Current connection status of the Wi-Fi transport.
    @Published public private(set) var connectionStatus: ConnectionStatus = .disconnected

    /// Information about the currently connected companion device.
    @Published public private(set) var connectedDevice: DeviceInfo? = nil

    /// Real-time measured round-trip latency in milliseconds.
    @Published public private(set) var latency: Double = 0.0

    /// List of discovered Bonjour peers.
    @Published public private(set) var discoveredDevices: [DeviceInfo] = []

    /// Whether Bonjour service discovery is actively running.
    @Published public private(set) var isScanning: Bool = false

    // MARK: - Private Properties

    /// Active network connection to the companion host.
    private var connection: NWConnection?

    /// Bonjour service browser instance.
    private var browser: NWBrowser?

    /// Mapping of device IDs to resolved network endpoints.
    private var endpointsMap: [String: NWEndpoint] = [:]

    /// Dedicated dispatch queue for network socket operations.
    private let networkQueue = DispatchQueue(label: "com.vntm.gamepad.wifi.queue", qos: .userInteractive)

    /// Timer for periodic ping packet transmission.
    private var pingTimer: AnyCancellable?

    /// Native unified logger.
    private let logger = Logger(subsystem: "com.vntm.gamepad", category: "WiFi")

    // MARK: - Initialization

    public init() {
        AppLog.info("WiFiService initialized. Ready for Bonjour discovery.", category: .wifi)
    }

    deinit {
        disconnect()
        stopDiscovery()
    }

    // MARK: - Discovery

    /// Starts Bonjour service discovery for nearby VNTM companion servers.
    public func startDiscovery() {
        guard !isScanning else {
            logger.debug("Bonjour discovery already in progress.")
            return
        }

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: Self.bonjourServiceType, domain: nil), using: parameters)
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            self?.handleBrowseResults(results)
        }

        browser.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isScanning = true
                    self?.logger.info("Bonjour browser ready and scanning for \(Self.bonjourServiceType).")
                    AppLog.info("Scanning for Wi-Fi companions via Bonjour...", category: .wifi)
                case .failed(let error):
                    self?.isScanning = false
                    self?.logger.error("Bonjour browser failed: \(error.localizedDescription)")
                    AppLog.error("Bonjour scan failed: \(error.localizedDescription)", category: .wifi)
                case .cancelled:
                    self?.isScanning = false
                    self?.logger.info("Bonjour browser cancelled.")
                default:
                    break
                }
            }
        }

        browser.start(queue: networkQueue)
    }

    /// Stops active Bonjour service discovery.
    public func stopDiscovery() {
        guard isScanning || browser != nil else { return }

        browser?.cancel()
        browser = nil

        DispatchQueue.main.async { [weak self] in
            self?.isScanning = false
            AppLog.info("Stopped Bonjour discovery.", category: .wifi)
        }
    }

    /// Processes browser results and updates `discoveredDevices`.
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        var devices: [DeviceInfo] = []
        var endpointMapping: [String: NWEndpoint] = [:]

        for result in results {
            let endpoint = result.endpoint
            var deviceName = "VNTM Host"
            var deviceId = ""

            switch endpoint {
            case .service(let name, _, _, _):
                deviceName = name
                deviceId = "bonjour_\(name)"
            case .hostPort(let host, let port):
                deviceName = "\(host):\(port)"
                deviceId = "\(host):\(port)"
            default:
                deviceId = endpoint.debugDescription
            }

            endpointMapping[deviceId] = endpoint

            let info = DeviceInfo(
                id: deviceId,
                name: deviceName,
                connectionType: .wifi,
                lastConnected: nil,
                signalStrength: nil
            )
            devices.append(info)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.endpointsMap = endpointMapping
            self.discoveredDevices = devices
            self.logger.debug("Discovered \(devices.count) Wi-Fi device(s).")
        }
    }

    // MARK: - Connection Management

    /// Connects to a specific discovered DeviceInfo.
    /// - Parameter device: The discovered peer device.
    public func connect(to device: DeviceInfo) {
        if let endpoint = endpointsMap[device.id] {
            connect(to: endpoint, deviceName: device.name)
        } else {
            // Attempt to parse host and port from ID if structured as host:port
            let components = device.id.components(separatedBy: ":")
            if components.count == 2, let port = UInt16(components[1]) {
                connect(host: components[0], port: port)
            } else {
                logger.error("Unable to resolve endpoint for device: \(device.id)")
                AppLog.error("Cannot connect: unresolved endpoint for \(device.name)", category: .wifi)
                connectionStatus = .error
            }
        }
    }

    /// Connects to a remote host and TCP port.
    /// - Parameters:
    ///   - host: Hostname or IPv4/IPv6 IP address string.
    ///   - port: TCP port number (defaults to `WiFiService.defaultPort` = 7777).
    public func connect(host: String, port: UInt16 = WiFiService.defaultPort) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            logger.error("Invalid port: \(port)")
            connectionStatus = .error
            return
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        connect(to: endpoint, deviceName: "\(host):\(port)")
    }

    /// Internal method to establish a connection to an NWEndpoint.
    private func connect(to endpoint: NWEndpoint, deviceName: String) {
        disconnect()

        DispatchQueue.main.async { [weak self] in
            self?.connectionStatus = .connecting
        }

        // Configure TCP parameters with fast-path options
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true // Disable Nagle's algorithm for minimum latency
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2

        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.includePeerToPeer = true

        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionStateChange(state, deviceName: deviceName)
        }

        logger.info("Opening TCP connection to \(endpoint.debugDescription)...")
        AppLog.info("Connecting to Wi-Fi host at \(deviceName)...", category: .wifi)

        connection.start(queue: networkQueue)
    }

    /// Disconnects the active TCP connection.
    public func disconnect() {
        stopPingTimer()

        if let conn = connection {
            logger.info("Closing active TCP connection.")
            conn.cancel()
            connection = nil
        }

        DispatchQueue.main.async { [weak self] in
            self?.connectionStatus = .disconnected
            self?.connectedDevice = nil
            self?.latency = 0.0
            AppLog.info("Wi-Fi connection closed.", category: .wifi)
        }
    }

    /// Sends raw binary data across the TCP connection.
    /// - Parameter data: State packet or command bytes.
    public func send(_ data: Data) {
        guard let connection = connection, connectionStatus == .connected else {
            logger.warning("Dropped send: Wi-Fi connection not connected.")
            return
        }

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.logger.error("TCP send error: \(error.localizedDescription)")
            }
        })
    }

    // MARK: - Connection State Handling

    /// Processes NWConnection state changes.
    private func handleConnectionStateChange(_ state: NWConnection.State, deviceName: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch state {
            case .setup:
                self.logger.debug("TCP connection setup.")
                self.connectionStatus = .connecting

            case .preparing:
                self.logger.debug("TCP connection preparing...")
                self.connectionStatus = .connecting

            case .ready:
                self.logger.info("TCP connection ready to \(deviceName).")
                AppLog.info("Connected to Wi-Fi companion (\(deviceName)).", category: .wifi)
                self.connectionStatus = .connected
                self.connectedDevice = DeviceInfo(
                    id: deviceName,
                    name: deviceName,
                    connectionType: .wifi,
                    lastConnected: Date(),
                    signalStrength: nil
                )
                self.startReceiving()
                self.startPingTimer()

            case .waiting(let error):
                self.logger.warning("TCP connection waiting: \(error.localizedDescription)")
                AppLog.warning("Wi-Fi connection waiting: \(error.localizedDescription)", category: .wifi)
                self.connectionStatus = .error

            case .failed(let error):
                self.logger.error("TCP connection failed: \(error.localizedDescription)")
                AppLog.error("Wi-Fi connection failed: \(error.localizedDescription)", category: .wifi)
                self.connectionStatus = .error
                self.disconnect()

            case .cancelled:
                self.logger.info("TCP connection cancelled.")
                self.connectionStatus = .disconnected
                self.connectedDevice = nil
                self.stopPingTimer()

            @unknown default:
                break
            }
        }
    }

    // MARK: - Packet Ingestion & Latency Tracking

    /// Starts the continuous reception loop on the TCP socket.
    private func startReceiving() {
        guard let connection = connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }

            if let data = content, !data.isEmpty {
                self.processIncomingData(data)
            }

            if isComplete {
                self.logger.info("Remote host closed TCP stream.")
                self.disconnect()
            } else if let error = error {
                self.logger.error("TCP receive error: \(error.localizedDescription)")
                self.disconnect()
            } else {
                // Continue reading next chunk
                self.startReceiving()
            }
        }
    }

    /// Evaluates incoming payload for ping/pong control packets or companion acknowledgements.
    private func processIncomingData(_ data: Data) {
        guard data.count >= 4 else { return }

        let bytes = [UInt8](data)

        // Check for PONG response: 'P' 'O' 'N' 'G' followed by 8-byte sent timestamp
        if bytes.starts(with: Self.pongHeader), data.count >= 12 {
            let sentTime = UInt64(bigEndianBytes: bytes, offset: 4)
            let currentTime = Date.monotonicMilliseconds
            if currentTime >= sentTime {
                let roundTrip = Double(currentTime - sentTime)
                DispatchQueue.main.async { [weak self] in
                    self?.latency = roundTrip
                }
                logger.debug("Received PONG. Latency: \(roundTrip) ms")
            }
        }
        // Check for PING request from companion: respond with PONG
        else if bytes.starts(with: Self.pingHeader), data.count >= 12 {
            var response = Data(Self.pongHeader)
            response.append(data.subdata(in: 4..<12))
            send(response)
        }
    }

    /// Starts periodic transmission of ping packets to gauge round-trip latency.
    private func startPingTimer() {
        stopPingTimer()
        // Transmit ping packet every 1.0 second
        pingTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sendPingPacket()
            }
    }

    /// Stops ping timer.
    private func stopPingTimer() {
        pingTimer?.cancel()
        pingTimer = nil
    }

    /// Constructs and sends a ping packet.
    private func sendPingPacket() {
        guard connectionStatus == .connected else { return }

        var packet = Data(Self.pingHeader)
        let timestamp = Date.monotonicMilliseconds
        packet.append(contentsOf: timestamp.bigEndianBytes)

        send(packet)
    }
}
