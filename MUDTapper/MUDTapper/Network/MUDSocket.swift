import Foundation
import Network
import SystemConfiguration
import UIKit
import AVFoundation

protocol MUDSocketDelegate: AnyObject {
    func mudSocket(_ socket: MUDSocket, didConnectToHost host: String, port: UInt16)
    func mudSocket(_ socket: MUDSocket, didDisconnectWithError error: Error?)
    func mudSocket(_ socket: MUDSocket, didReceiveData data: Data)
    func mudSocket(_ socket: MUDSocket, didWriteDataWithTag tag: Int)
}

class MUDSocket: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: MUDSocketDelegate?
    
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.mudtapper.socket", qos: .userInitiated)
    private var keepAliveTimer: Timer?
    private var reconnectTimer: Timer?
    private var lastActivityTime: Date = Date()
    private var isInBackground = false
    private var shouldReconnect = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = Int.max
    private let reconnectDelay: TimeInterval = 2.0
    
    // Background task management
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var backgroundKeepAliveTimer: Timer?
    private var connectionMaintenanceTask: UIBackgroundTaskIdentifier = .invalid
    private var backgroundTaskStartTime: Date?
    private var voipBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // Enhanced background connection maintenance
    private var connectionLossDetectionTimer: Timer?
    private var lastDataReceiveTime: Date = Date()
    private var consecutiveKeepAliveFailures = 0
    private var backgroundTaskChainTimer: Timer?
    private var isInDeepBackground = false
    private var pathMonitor: NWPathMonitor?
    
    // Network reachability monitoring
    private var reachability: SCNetworkReachability?
    private var lastNetworkStatus: SCNetworkReachabilityFlags?
    private var isMonitoringNetwork = false
    
    // VoIP socket support for enhanced background protection
    private var isVoIPSocketEnabled = false
    private var voipSocket: CFSocket?
    private var voipSocketSource: CFRunLoopSource?
    
    // Connection state tracking
    private var lastSuccessfulDataTime: Date = Date()
    private var connectionHealthCheckTimer: Timer?
    
    // Connection persistence scoring
    private var connectionQualityScore: Int = 100  // Start with perfect score
    private var backgroundSuccessfulKeepalives: Int = 0
    private var backgroundFailedKeepalives: Int = 0
    
    var isConnected: Bool {
        return connection?.state == .ready
    }
    
    var connectionState: NWConnection.State? {
        return connection?.state
    }
    
    var connectedHost: String?
    var connectedPort: UInt16 = 0
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupAppStateNotifications()
    }
    
    deinit {
        disconnect()
        NotificationCenter.default.removeObserver(self)
        stopNetworkMonitoring()
        stopPathMonitoring()
        endConnectionMaintenanceTask()
        endBackgroundTask()
        disableVoIPBackgroundProtection()
    }
    
    // MARK: - MSDP Support
    
    /// Send an MSDP variable to the server
    /// - Parameters:
    ///   - variable: The MSDP variable name (e.g., "XTERM_256_COLORS")
    ///   - value: The value to send (e.g., "1")
    func sendMSDP(variable: String, value: String) {
        guard connection?.state == .ready else {
            print("MUDSocket: Cannot send MSDP - connection not ready")
            return
        }
        
        // MSDP format: IAC SB MSDP variable MSDP_VAL value IAC SE
        var msdpData: [UInt8] = [
            255, 250, 69, // IAC SB MSDP
        ]
        
        // Add variable name
        msdpData.append(contentsOf: variable.utf8)
        
        // Add MSDP_VAL separator
        msdpData.append(1) // MSDP_VAL
        
        // Add value
        msdpData.append(contentsOf: value.utf8)
        
        // Add IAC SE
        msdpData.append(contentsOf: [255, 240]) // IAC SE
        
        let data = Data(msdpData)
        
        // Debug logging
        print("MUDSocket: Sending MSDP \(variable)=\(value)")
        print("MUDSocket: MSDP bytes: \(msdpData.map { String(format: "%02x", $0) }.joined(separator: " "))")
        print("MUDSocket: MSDP data length: \(data.count) bytes")
        
        // Log the actual bytes being sent
        let hexString = data.map { String(format: "%02x", $0) }.joined(separator: " ")
        print("MUDSocket: Raw MSDP data: \(hexString)")
        
        send(data)
    }
    
    /// Send XTERM_256_COLORS=1 to enable 256-color support
    func sendXterm256Colors() {
        sendMSDP(variable: "XTERM_256_COLORS", value: "1")
    }

    // MARK: - Connection Management
    
    func connect(to hostname: String, port: UInt16, timeout: TimeInterval = 30.0) throws {
        guard !hostname.isEmpty else {
            throw MUDSocketError.invalidHostname
        }
        
        guard port > 0 else {
            throw MUDSocketError.invalidPort
        }
        
        // Validate hostname format
        guard isValidHostname(hostname) else {
            throw MUDSocketError.invalidHostname
        }
        
        print("MUDSocket: Attempting to connect to \(hostname):\(port)")
        
        if connection != nil {
            disconnect()
        }
        
        let host = NWEndpoint.Host(hostname)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        
        // Create enhanced connection parameters for MUD client
        let parameters = NWParameters.tcp
        
        // Configure for interactive, low-latency communication
        parameters.serviceClass = .interactiveVoice
        parameters.multipathServiceType = .interactive
        // Allow any interface (WiFi or Cellular). Do not restrict interface type.
        
        // Configure TCP options for MUD gaming
        if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 15      // Start keep-alive after 15s of inactivity (was 30s)
            tcpOptions.keepaliveInterval = 5   // Send keep-alive every 5s (was 10s)
            tcpOptions.keepaliveCount = 6      // Allow 6 failed keep-alives before considering dead (was 3)
            tcpOptions.noDelay = true          // Disable Nagle's algorithm for low latency
            tcpOptions.connectionTimeout = 30  // 30 second connection timeout
            
            // Add more aggressive socket options for background stability
            tcpOptions.enableFastOpen = false  // Disable TCP Fast Open for stability
            tcpOptions.disableAckStretching = true  // Prevent delayed ACKs for real-time gaming
        }
        
        connection = NWConnection(host: host, port: nwPort, using: parameters)
        
        connection?.stateUpdateHandler = { [weak self] state in
            self?.handleStateUpdate(state)
        }
        
        connection?.start(queue: queue)
        
        connectedHost = hostname
        connectedPort = port
        shouldReconnect = true
        reconnectAttempts = 0
        
        // Enable VoIP background protection for persistent connection
        enableVoIPBackgroundProtection()
        
        // Start network monitoring
        setupNetworkMonitoring()
        startPathMonitoring()
        
        #if DEBUG
        print("MUDSocket: Connection started, waiting for state updates...")
        #endif
    }
    
    func disconnect() {
        stopKeepAliveTimer()
        stopReconnectTimer()
        stopNetworkMonitoring()
        endConnectionMaintenanceTask()
        endBackgroundTask()
        disableVoIPBackgroundProtection()
        connection?.cancel()
        connection = nil
        connectedHost = nil
        connectedPort = 0
        shouldReconnect = false
        reconnectAttempts = 0
    }
    
    // MARK: - Data Transmission
    
    func send(_ text: String, encoding: String.Encoding = .utf8) {
        guard let connection = connection, connection.state == .ready else { return }
        
        var dataToSend = text
        
        // Normalize line endings to CRLF
        if dataToSend.hasSuffix("\r\n") {
            // already normalized
        } else if dataToSend.hasSuffix("\n") {
            dataToSend = String(dataToSend.dropLast()) + "\r\n"
        } else if dataToSend.isEmpty {
            dataToSend = "\r\n"
        } else {
            dataToSend += "\r\n"
        }
        
        guard let data = dataToSend.data(using: encoding) else {
            print("Failed to encode text: \(text)")
            return
        }
        
        send(data)
    }
    
    func send(_ data: Data) {
        guard let connection = connection, connection.state == .ready else { 
            print("MUDSocket: Cannot send data - connection not ready")
            return 
        }
        
        #if DEBUG
        print("MUDSocket: Sending \(data.count) bytes of data")
        #endif
        
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            DispatchQueue.main.async {
                guard let strongSelf = self else { return }
                if let error = error {
                    #if DEBUG
                    print("MUDSocket: Send error: \(error)")
                    #endif
                } else {
                    #if DEBUG
                    print("MUDSocket: Data sent successfully")
                    #endif
                    strongSelf.lastActivityTime = Date()
                    strongSelf.delegate?.mudSocket(strongSelf, didWriteDataWithTag: 0)
                }
            }
        })
    }
    
    // MARK: - Background App Handling
    
    private func setupAppStateNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: .appDidBecomeActive,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: .appDidEnterBackground,
            object: nil
        )
    }
    
    @objc private func handleAppDidBecomeActive() {
        isInBackground = false
        isInDeepBackground = false
        #if DEBUG
        print("MUDSocket: App became active")
        #endif
        
        // End all background tasks and timers
        endConnectionMaintenanceTask()
        endBackgroundTask()
        stopConnectionLossDetection()
        stopBackgroundTaskChaining()
        
        // Reset failure counters
        consecutiveKeepAliveFailures = 0
        
        // Check connection status and reconnect if needed
        if shouldReconnect && connectedHost != nil {
            if isConnected {
                #if DEBUG
                print("MUDSocket: Testing connection health after app resume")
                #endif
                testConnectionHealth { [weak self] isHealthy in
                    if isHealthy {
                        #if DEBUG
                        print("MUDSocket: Connection is healthy, resuming normal operation")
                        #endif
                        self?.startKeepAliveTimer()
                    } else {
                        #if DEBUG
                        print("MUDSocket: Connection is unhealthy, attempting reconnection")
                        #endif
                        self?.attemptReconnect()
                    }
                }
            } else {
                #if DEBUG
                print("MUDSocket: Not connected, attempting to reconnect after app became active")
                #endif
                attemptReconnect()
            }
        }
    }
    
    @objc private func handleAppDidEnterBackground() {
        isInBackground = true
        #if DEBUG
        print("MUDSocket: App entered background")
        #endif
        
        // Stop foreground keep-alive timer
        stopKeepAliveTimer()
        
        // Start comprehensive background protection for network connection
        if isConnected {
            startConnectionMaintenanceTask()
            
            // Send immediate keep-alive to ensure connection is still active
            sendKeepAlive()
            
            // Start connection loss detection
            startConnectionLossDetection()
            
            // Set up background task chaining for extended background time
            startBackgroundTaskChaining()
            
            #if DEBUG
            print("MUDSocket: Started comprehensive connection maintenance for background")
            #endif
        }
    }
    
    // MARK: - Keep-Alive and Reconnection
    
    private func startKeepAliveTimer() {
        stopKeepAliveTimer()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.sendKeepAlive()
        }
    }
    
    private func stopKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }
    
    private func sendKeepAlive() {
        // Send a simple keep-alive command (usually just a newline)
        // This prevents the server from timing out the connection
        guard isConnected else {
            print("MUDSocket: Cannot send keep-alive, not connected")
            return
        }
        
        print("MUDSocket: Sending keep-alive")
        lastActivityTime = Date()
        
        // Use different keep-alive strategies based on background state
        let keepAliveData: Data
        if isInBackground {
            // In background, use a more substantial keep-alive that might provoke a response
            if isInDeepBackground {
                // Deep background - use a command that should definitely get a response
                // Rotate between different commands to avoid server-side filtering
                let commands = ["look", "score", "time", "who"]
                let randomCommand = commands.randomElement() ?? "look"
                keepAliveData = "\(randomCommand)\n".data(using: .utf8) ?? "\n".data(using: .utf8)!
            } else {
                // Normal background - use a minimal but trackable command
                // Some MUDs respond to empty commands, others ignore them
                keepAliveData = " \n".data(using: .utf8) ?? "\n".data(using: .utf8)!
            }
        } else {
            // Foreground - just send a newline (most servers echo this or ignore silently)
            keepAliveData = "\n".data(using: .utf8)!
        }
        
        // Send with completion tracking for background failure detection
        connection?.send(content: keepAliveData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("MUDSocket: Keep-alive send failed: \(error)")
                if self?.isInBackground == true {
                    self?.consecutiveKeepAliveFailures += 1
                    self?.backgroundFailedKeepalives += 1
                    self?.updateConnectionQuality(success: false)
                    print("MUDSocket: Keep-alive failures: \(self?.consecutiveKeepAliveFailures ?? 0)")
                    
                    // If multiple failures in background, consider connection problematic
                    if self?.consecutiveKeepAliveFailures ?? 0 >= 2 {
                        print("MUDSocket: Multiple keep-alive failures, connection may be lost")
                        DispatchQueue.main.async {
                            self?.handleBackgroundConnectionLoss()
                        }
                    }
                }
            } else {
                print("MUDSocket: Keep-alive sent successfully")
                self?.consecutiveKeepAliveFailures = 0
                if self?.isInBackground == true {
                    self?.backgroundSuccessfulKeepalives += 1
                    self?.updateConnectionQuality(success: true)
                }
            }
        })
    }
    
    private func attemptReconnect() {
        guard shouldReconnect && reconnectAttempts < maxReconnectAttempts else {
            print("MUDSocket: Max reconnection attempts reached or reconnection disabled")
            return
        }
        
        reconnectAttempts += 1
        #if DEBUG
        print("MUDSocket: Attempting reconnection \(reconnectAttempts)/\(maxReconnectAttempts)")
        #endif
        
        guard let host = connectedHost, connectedPort > 0 else {
            #if DEBUG
            print("MUDSocket: No connection info available for reconnection")
            #endif
            return
        }
        
        do {
            try connect(to: host, port: connectedPort)
        } catch {
            #if DEBUG
            print("MUDSocket: Reconnection failed: \(error)")
            #endif
            scheduleReconnectAttempt()
        }
    }
    
    private func scheduleReconnectAttempt() {
        stopReconnectTimer()
        let delay = min(2.0 * Double(reconnectAttempts), 10.0) // Exponential backoff, max 10 seconds
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.attemptReconnect()
        }
    }
    
    private func stopReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    // MARK: - Background Task Management
    
    private func startConnectionMaintenanceTask() {
        // End any existing tasks first
        endConnectionMaintenanceTask()
        endBackgroundTask()
        
        #if DEBUG
        print("MUDSocket: Starting connection maintenance task")
        #endif
        backgroundTaskStartTime = Date()
        
        connectionMaintenanceTask = UIApplication.shared.beginBackgroundTask(withName: "MUDSocket-ConnectionMaintenance") { [weak self] in
            #if DEBUG
            print("MUDSocket: Connection maintenance task expired")
            #endif
            self?.handleBackgroundTaskExpiration()
        }
        
        if connectionMaintenanceTask == .invalid {
            #if DEBUG
            print("MUDSocket: Failed to start connection maintenance task")
            #endif
            return
        }
        
        #if DEBUG
        print("MUDSocket: Connection maintenance task started with ID: \(connectionMaintenanceTask.rawValue)")
        #endif
        
        // Start aggressive background keep-alive
        startBackgroundKeepAlive(interval: getAdaptiveKeepAliveInterval())
        
        // Monitor background time remaining
        startBackgroundTimeMonitoring()
    }
    
    private func endConnectionMaintenanceTask() {
        guard connectionMaintenanceTask != .invalid else { return }
        
        #if DEBUG
        print("MUDSocket: Ending connection maintenance task")
        #endif
        stopBackgroundKeepAlive()
        stopBackgroundTimeMonitoring()
        
        UIApplication.shared.endBackgroundTask(connectionMaintenanceTask)
        connectionMaintenanceTask = .invalid
        backgroundTaskStartTime = nil
    }
    
    private func handleBackgroundTaskExpiration() {
        #if DEBUG
        print("MUDSocket: Background task expiring - implementing graceful degradation")
        #endif
        
        // This is called when iOS is about to suspend the app
        // We need to handle this quickly to avoid being killed by the watchdog
        
        // Stop all timers immediately
        stopBackgroundKeepAlive()
        stopBackgroundTimeMonitoring()
        
        if isConnected {
            // Send a final keep-alive if possible (non-blocking)
            #if DEBUG
            print("MUDSocket: Sending final keep-alive before suspension")
            #endif
            sendKeepAlive()
            
            // Note: We deliberately do NOT disconnect here
            // The connection will be tested when the app resumes
            // This allows for quick recovery if the suspension was brief
        }
        
        // End the task
        endConnectionMaintenanceTask()
    }
    
    private func startBackgroundTimeMonitoring() {
        // Monitor remaining background time and adapt strategy
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            let backgroundTimeRemaining = UIApplication.shared.backgroundTimeRemaining
            let taskDuration = self.backgroundTaskStartTime?.timeIntervalSinceNow ?? 0
            
            #if DEBUG
            print("MUDSocket: Background time remaining: \(backgroundTimeRemaining)s, task duration: \(-taskDuration)s")
            #endif
            
            // If we're running low on time, reduce keep-alive frequency
            if backgroundTimeRemaining < 30 {
                #if DEBUG
                print("MUDSocket: Low background time remaining, reducing keep-alive frequency")
                #endif
                self.stopBackgroundKeepAlive()
                // Send one final keep-alive
                self.sendKeepAlive()
                timer.invalidate()
            } else if backgroundTimeRemaining < 60 {
                // Reduce frequency to every 20 seconds
                self.stopBackgroundKeepAlive()
                self.startBackgroundKeepAlive(interval: 20.0)
            }
            
            // Stop monitoring if task is no longer valid
            if self.connectionMaintenanceTask == .invalid {
                timer.invalidate()
            }
        }
    }
    
    private func stopBackgroundTimeMonitoring() {
        // Timer will be invalidated by the monitoring logic itself
    }
    
    private func startBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        
        #if DEBUG
        print("MUDSocket: Starting legacy background task")
        #endif
        backgroundTask = UIApplication.shared.beginBackgroundTask(expirationHandler: { [weak self] in
            #if DEBUG
            print("MUDSocket: Legacy background task expired")
            #endif
            self?.endBackgroundTask()
        })
        
        if backgroundTask == .invalid {
            #if DEBUG
            print("MUDSocket: Failed to start legacy background task")
            #endif
        }
    }
    
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        
        #if DEBUG
        print("MUDSocket: Ending legacy background task")
        #endif
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
    
    private func startBackgroundKeepAlive(interval: TimeInterval = 10.0) {
        stopBackgroundKeepAlive()
        
        #if DEBUG
        print("MUDSocket: Starting background keep-alive with \(interval)s interval")
        #endif
        
        // Send keep-alive every specified interval in background
        backgroundKeepAliveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.isConnected {
                #if DEBUG
                print("MUDSocket: Sending background keep-alive")
                #endif
                self.sendKeepAlive()
                
                // Adaptive frequency based on background time remaining
                let backgroundTimeRemaining = UIApplication.shared.backgroundTimeRemaining
                if backgroundTimeRemaining < 60 && interval < 15.0 {
                    // If we're running low on background time, reduce frequency
                    #if DEBUG
                    print("MUDSocket: Reducing keep-alive frequency due to limited background time")
                    #endif
                    self.stopBackgroundKeepAlive()
                    self.startBackgroundKeepAlive(interval: 15.0)
                } else if backgroundTimeRemaining > 120 && interval > 8.0 {
                    // If we have plenty of background time, increase frequency
                    #if DEBUG
                    print("MUDSocket: Increasing keep-alive frequency with abundant background time")
                    #endif
                    self.stopBackgroundKeepAlive()
                    self.startBackgroundKeepAlive(interval: 8.0)
                }
            } else {
                #if DEBUG
                print("MUDSocket: Not connected, stopping background keep-alive")
                #endif
                self.stopBackgroundKeepAlive()
            }
        }
    }
    
    private func stopBackgroundKeepAlive() {
        backgroundKeepAliveTimer?.invalidate()
        backgroundKeepAliveTimer = nil
    }
    
    // MARK: - Network Reachability Monitoring
    
    private func setupNetworkMonitoring() {
        guard let host = connectedHost, !isMonitoringNetwork else { return }
        
        #if DEBUG
        print("MUDSocket: Setting up network monitoring for \(host)")
        #endif
        
        // Create reachability reference
        reachability = SCNetworkReachabilityCreateWithName(nil, host)
        
        guard let reachability = reachability else {
            #if DEBUG
            print("MUDSocket: Failed to create reachability reference")
            #endif
            return
        }
        
        // Set up callback
        var context = SCNetworkReachabilityContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        
        let callback: SCNetworkReachabilityCallBack = { (reachability, flags, info) in
            guard let info = info else { return }
            let socket = Unmanaged<MUDSocket>.fromOpaque(info).takeUnretainedValue()
            socket.handleNetworkChange(flags: flags)
        }
        
        if SCNetworkReachabilitySetCallback(reachability, callback, &context) {
            if SCNetworkReachabilityScheduleWithRunLoop(reachability, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                isMonitoringNetwork = true
                #if DEBUG
                print("MUDSocket: Network monitoring started")
                #endif
                
                // Get initial status
                var flags = SCNetworkReachabilityFlags()
                if SCNetworkReachabilityGetFlags(reachability, &flags) {
                    lastNetworkStatus = flags
                    #if DEBUG
                    print("MUDSocket: Initial network status: \(flags)")
                    #endif
                }
            } else {
                #if DEBUG
                print("MUDSocket: Failed to schedule network monitoring")
                #endif
            }
        } else {
            #if DEBUG
            print("MUDSocket: Failed to set network monitoring callback")
            #endif
        }
    }
    
    private func stopNetworkMonitoring() {
        guard let reachability = reachability, isMonitoringNetwork else { return }
        
        SCNetworkReachabilityUnscheduleFromRunLoop(reachability, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        self.reachability = nil
        isMonitoringNetwork = false
        lastNetworkStatus = nil
        #if DEBUG
        print("MUDSocket: Network monitoring stopped")
        #endif
    }
    
    // MARK: - NWPath monitoring
    private func startPathMonitoring() {
        stopPathMonitoring()
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            #if DEBUG
            print("MUDSocket: NWPath update: status=\(path.status), expensive=\(path.isExpensive), constrained=\(path.isConstrained)")
            #endif
            if path.status == .satisfied {
                if self.shouldReconnect && !self.isConnected {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.attemptReconnect()
                    }
                }
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }
    
    private func stopPathMonitoring() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }
    
    private func handleNetworkChange(flags: SCNetworkReachabilityFlags) {
        #if DEBUG
        print("MUDSocket: Network status changed: \(flags)")
        #endif
        
        let wasReachable = lastNetworkStatus?.contains(.reachable) ?? false
        let isReachable = flags.contains(.reachable)
        
        // Check if network interface changed (WiFi to cellular or vice versa)
        let interfaceChanged = lastNetworkStatus != nil && lastNetworkStatus != flags
        
        // Log network interface type
        let interfaceType = getNetworkInterfaceType(flags: flags)
        #if DEBUG
        print("MUDSocket: Current network interface: \(interfaceType)")
        #endif
        
        lastNetworkStatus = flags
        
        if interfaceChanged {
            #if DEBUG
            print("MUDSocket: Network interface changed, connection may be affected")
            #endif
            
            // If we were connected and network interface changed, attempt reconnection
            if isConnected && isReachable {
                #if DEBUG
                print("MUDSocket: Network interface changed, attempting reconnection")
                #endif
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.attemptReconnectionAfterNetworkChange()
                }
            }
        }
        
        if !wasReachable && isReachable {
            #if DEBUG
            print("MUDSocket: Network became reachable")
            #endif
            // Network became available, try to reconnect if we should be connected
            if shouldReconnect && !isConnected {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.attemptReconnect()
                }
            }
        } else if wasReachable && !isReachable {
            #if DEBUG
            print("MUDSocket: Network became unreachable")
            #endif
            // Network became unavailable, this will be handled by connection failure
        }
    }
    
    private func getNetworkInterfaceType(flags: SCNetworkReachabilityFlags) -> String {
        if flags.contains(.isWWAN) {
            return "Cellular"
        } else if flags.contains(.reachable) {
            return "WiFi"
        } else {
            return "None"
        }
    }
    
    private func attemptReconnectionAfterNetworkChange() {
        guard shouldReconnect && connectedHost != nil else { return }
        
        #if DEBUG
        print("MUDSocket: Attempting reconnection after network interface change")
        #endif
        
        // Force disconnect current connection
        connection?.cancel()
        connection = nil
        
        // Reset reconnection attempts for network change
        reconnectAttempts = 0
        
        // Attempt to reconnect
        attemptReconnect()
    }
    
    // MARK: - VoIP Socket Configuration
    
    /// Enable VoIP socket protection for background operation
    /// This provides the strongest background protection available on iOS
    func enableVoIPBackgroundProtection() {
        guard !isVoIPSocketEnabled else { return }
        
        #if DEBUG
        print("MUDSocket: Enabling VoIP background protection")
        #endif
        isVoIPSocketEnabled = true
        
        // Start VoIP background task
        startVoIPBackgroundTask()
        
        // Configure connection for VoIP if already connected
        if let connection = self.connection {
            configureConnectionForVoIP(connection)
        }
    }
    
    /// Disable VoIP socket protection
    func disableVoIPBackgroundProtection() {
        guard isVoIPSocketEnabled else { return }
        
        #if DEBUG
        print("MUDSocket: Disabling VoIP background protection")
        #endif
        isVoIPSocketEnabled = false
        
        cleanupVoIPSocket()
        endVoIPBackgroundTask()
    }
    
    private func configureConnectionForVoIP(_ connection: NWConnection) {
        // Configure connection parameters for VoIP
        let parameters = NWParameters.tcp
        parameters.serviceClass = .interactiveVoice
        parameters.multipathServiceType = .interactive
        
        // Enable keep-alive at the TCP level
        if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 30
            tcpOptions.keepaliveInterval = 10
            tcpOptions.keepaliveCount = 3
            tcpOptions.noDelay = true
        }
        
        #if DEBUG
        print("MUDSocket: Configured connection for VoIP operation")
        #endif
    }
    
    private func startVoIPBackgroundTask() {
        endVoIPBackgroundTask() // Clean up any existing task
        
        #if DEBUG
        print("MUDSocket: Starting VoIP background task")
        #endif
        voipBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "MUDSocket-VoIP-Protection") { [weak self] in
            #if DEBUG
            print("MUDSocket: VoIP background task expired")
            #endif
            self?.handleVoIPBackgroundTaskExpiration()
        }
        
        if voipBackgroundTask == .invalid {
            #if DEBUG
            print("MUDSocket: Failed to start VoIP background task")
            #endif
        }
    }
    
    private func endVoIPBackgroundTask() {
        guard voipBackgroundTask != .invalid else { return }
        
        #if DEBUG
        print("MUDSocket: Ending VoIP background task")
        #endif
        UIApplication.shared.endBackgroundTask(voipBackgroundTask)
        voipBackgroundTask = .invalid
    }
    
    private func handleVoIPBackgroundTaskExpiration() {
        #if DEBUG
        print("MUDSocket: VoIP background task expiring - attempting to maintain connection")
        #endif
        
        // Send keep-alive immediately
        sendKeepAlive()
        
        // Restart VoIP background task if still enabled
        if isVoIPSocketEnabled {
            startVoIPBackgroundTask()
        }
        
        endVoIPBackgroundTask()
    }
    
    private func cleanupVoIPSocket() {
        if let source = voipSocketSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
            voipSocketSource = nil
        }
        
        if let socket = voipSocket {
            CFSocketInvalidate(socket)
            voipSocket = nil
        }
    }
    
    // MARK: - Enhanced Background Connection Maintenance

    /// Start monitoring for connection loss in background
    private func startConnectionLossDetection() {
        stopConnectionLossDetection()
        
        #if DEBUG
        print("MUDSocket: Starting connection loss detection")
        #endif
        
        connectionLossDetectionTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let timeSinceLastData = Date().timeIntervalSince(self.lastDataReceiveTime)
            #if DEBUG
            print("MUDSocket: Time since last data: \(timeSinceLastData)s")
            #endif
            
            // If we haven't received data in 60 seconds, send a health check
            if timeSinceLastData > 60 {
                #if DEBUG
                print("MUDSocket: No data received for 60s, sending health check")
                #endif
                self.sendBackgroundHealthCheck()
            }
            
            // If no data for 120 seconds, consider connection lost
            if timeSinceLastData > 120 {
                #if DEBUG
                print("MUDSocket: Connection appears lost, attempting recovery")
                #endif
                self.handleBackgroundConnectionLoss()
            }
        }
    }

    private func stopConnectionLossDetection() {
        connectionLossDetectionTimer?.invalidate()
        connectionLossDetectionTimer = nil
    }

    /// Send a health check specifically designed for background operation
    private func sendBackgroundHealthCheck() {
        guard isConnected else { return }
        
        #if DEBUG
        print("MUDSocket: Sending background health check")
        #endif
        
        // Send a minimal command that should provoke a response
        let healthCheck = "look\n".data(using: .utf8)!
        
        connection?.send(content: healthCheck, completion: .contentProcessed { [weak self] error in
            if let error = error {
                #if DEBUG
                print("MUDSocket: Background health check failed: \(error)")
                #endif
                self?.consecutiveKeepAliveFailures += 1
                
                // If we've had multiple failures, attempt reconnection
                if self?.consecutiveKeepAliveFailures ?? 0 >= 3 {
                    #if DEBUG
                    print("MUDSocket: Multiple health check failures, attempting reconnection")
                    #endif
                    DispatchQueue.main.async {
                        self?.handleBackgroundConnectionLoss()
                    }
                }
            } else {
                #if DEBUG
                print("MUDSocket: Background health check succeeded")
                #endif
                self?.consecutiveKeepAliveFailures = 0
            }
        })
    }

    /// Handle connection loss detected during background operation
    private func handleBackgroundConnectionLoss() {
        #if DEBUG
        print("MUDSocket: Handling background connection loss")
        #endif
        
        // Mark as in deep background to use more aggressive reconnection
        isInDeepBackground = true
        
        // Force disconnect and attempt immediate reconnection
        connection?.cancel()
        connection = nil
        
        // Reset attempts for background recovery
        reconnectAttempts = 0
        
        // Attempt reconnection with shorter delay for background
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.attemptReconnect()
        }
    }

    /// Start background task chaining to extend background execution time
    private func startBackgroundTaskChaining() {
        stopBackgroundTaskChaining()
        
        #if DEBUG
        #if DEBUG
        print("MUDSocket: Starting background task chaining")
        #endif
        #endif
        
        // Chain background tasks every 25 seconds to maximize background time
        backgroundTaskChainTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let backgroundTimeRemaining = UIApplication.shared.backgroundTimeRemaining
            #if DEBUG
            #if DEBUG
            print("MUDSocket: Background time remaining: \(backgroundTimeRemaining)s")
            #endif
            #endif
            
            if backgroundTimeRemaining < 40 {
                #if DEBUG
                #if DEBUG
                print("MUDSocket: Low background time, creating new background task")
                #endif
                #endif
                self.chainBackgroundTask()
            }
            
            // Stop chaining if we're not supposed to be in background anymore
            if !self.isInBackground {
                self.stopBackgroundTaskChaining()
            }
        }
    }

    private func stopBackgroundTaskChaining() {
        backgroundTaskChainTimer?.invalidate()
        backgroundTaskChainTimer = nil
    }

    /// Create a new background task to extend execution time
    private func chainBackgroundTask() {
        // End current task
        endConnectionMaintenanceTask()
        
        // Start a new one
        startConnectionMaintenanceTask()
        
        #if DEBUG
        print("MUDSocket: Chained background task for extended execution")
        #endif
    }
    
    // MARK: - Connection Quality Management
    
    /// Update connection quality score based on keep-alive success/failure
    private func updateConnectionQuality(success: Bool) {
        if success {
            // Improve score gradually for successful keep-alives
            connectionQualityScore = min(100, connectionQualityScore + 1)
        } else {
            // Decrease score more aggressively for failures
            connectionQualityScore = max(0, connectionQualityScore - 5)
        }
        
        #if DEBUG
        print("MUDSocket: Connection quality score: \(connectionQualityScore)")
        #endif
    }
    
    /// Get adaptive keep-alive interval based on connection quality
    private func getAdaptiveKeepAliveInterval() -> TimeInterval {
        // Adjust keep-alive frequency based on connection quality
        if connectionQualityScore >= 80 {
            return 12.0  // Good connection - less frequent
        } else if connectionQualityScore >= 50 {
            return 8.0   // Moderate connection - more frequent  
        } else {
            return 5.0   // Poor connection - very frequent
        }
    }
    
    // MARK: - Private Methods
    
    private func handleStateUpdate(_ state: NWConnection.State) {
        #if DEBUG
        print("MUDSocket: State update: \(state)")
        #endif
        
        switch state {
        case .ready:
            #if DEBUG
            print("MUDSocket: Connection is ready")
            #endif
            reconnectAttempts = 0 // Reset reconnection attempts on successful connection
            // Send MSDP XTERM_256_COLORS=1 to server
            sendXterm256Colors()
            DispatchQueue.main.async {
                self.delegate?.mudSocket(self, didConnectToHost: self.connectedHost ?? "", port: self.connectedPort)
            }
            // Start receiving data now that connection is ready
            startReceiving()
            // Start keep-alive timer if not in background
            if !isInBackground {
                startKeepAliveTimer()
            }
            
        case .failed(let error):
            #if DEBUG
            print("MUDSocket: Connection failed with error: \(error)")
            #endif
            stopKeepAliveTimer()
            
            // Check if this might be due to socket resource reclamation
            let isResourceReclamation = isSocketResourceReclamationError(error)
            if isResourceReclamation {
                #if DEBUG
                print("MUDSocket: Detected socket resource reclamation")
                #endif
            }
            
            DispatchQueue.main.async {
                self.delegate?.mudSocket(self, didDisconnectWithError: error)
            }
            
            // Attempt reconnection if enabled
            if shouldReconnect {
                if isInBackground || isResourceReclamation {
                    // Quick reconnection attempt for resource reclamation or background
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.attemptReconnect()
                    }
                } else {
                    scheduleReconnectAttempt()
                }
            }
            
        case .cancelled:
            #if DEBUG
            print("MUDSocket: Connection was cancelled")
            #endif
            stopKeepAliveTimer()
            DispatchQueue.main.async {
                self.delegate?.mudSocket(self, didDisconnectWithError: nil)
            }
            // Don't attempt reconnection if manually cancelled
            shouldReconnect = false
            
        case .waiting(let error):
            #if DEBUG
            print("MUDSocket: Connection is waiting: \(error)")
            #endif
            
        case .preparing:
            #if DEBUG
            print("MUDSocket: Connection is preparing")
            #endif
            
        case .setup:
            #if DEBUG
            print("MUDSocket: Connection is setting up")
            #endif
            
        @unknown default:
            #if DEBUG
            print("MUDSocket: Unknown connection state: \(state)")
            #endif
        }
    }
    
    private func isSocketResourceReclamationError(_ error: Error) -> Bool {
        // Check for common errors that indicate socket resource reclamation
        let nsError = error as NSError
        
        // EBADF (Bad file descriptor) is a common sign of resource reclamation
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == EBADF {
            return true
        }
        
        // Check for NWError cases that might indicate resource issues
        if let nwError = error as? NWError {
            switch nwError {
            case .posix(let posixError):
                return posixError == .EBADF || posixError == .ENOTCONN || posixError == .EPIPE
            default:
                return false
            }
        }
        
        return false
    }
    
    private func startReceiving() {
        guard let connection = connection else { return }
        
        #if DEBUG
        print("MUDSocket: Starting to receive data...")
        #endif
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            #if DEBUG
            print("MUDSocket: Received callback - data: \(data?.count ?? 0) bytes, isComplete: \(isComplete), error: \(String(describing: error))")
            #endif
            
            if let data = data, !data.isEmpty {
                #if DEBUG
                print("MUDSocket: Received \(data.count) bytes of data")
                #endif
                
                // Update last data receive time for connection monitoring
                self?.lastDataReceiveTime = Date()
                self?.consecutiveKeepAliveFailures = 0 // Reset failure counter on successful data
                
                // Try multiple encodings commonly used by MUD servers
                _ = self?.decodeDataToString(data)
                
                let filtered = self?.handleTelnetNegotiation(data) ?? data
                DispatchQueue.main.async {
                    self?.delegate?.mudSocket(self!, didReceiveData: filtered)
                }
            } else {
                #if DEBUG
                print("MUDSocket: No data received")
                #endif
            }
            
            if let error = error {
                #if DEBUG
                print("MUDSocket: Receive error: \(error)")
                #endif
                DispatchQueue.main.async {
                    self?.delegate?.mudSocket(self!, didDisconnectWithError: error)
                }
                return
            }
            
            if isComplete {
                #if DEBUG
                print("MUDSocket: Connection completed")
                #endif
                DispatchQueue.main.async {
                    self?.delegate?.mudSocket(self!, didDisconnectWithError: nil)
                }
                return
            }
            
            // Continue receiving
            self?.startReceiving()
        }
    }
    
    private func decodeDataToString(_ data: Data) -> String? {
        // Try multiple encodings commonly used by MUD servers in order of preference
        let encodings: [String.Encoding] = [
            .utf8,                     // Modern standard
            .ascii,                    // Basic ASCII
            .isoLatin1,               // ISO-8859-1 (Latin-1) - very common for MUDs
            .windowsCP1252,           // Windows-1252 - common on Windows MUD servers
            .utf16,                   // UTF-16
            .macOSRoman              // Classic Mac encoding
        ]
        
        for encoding in encodings {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }
        
        return nil
    }
    
    private func isValidHostname(_ hostname: String) -> Bool {
        // Basic hostname validation
        let hostnameRegex = "^[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?([.][a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?)*$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", hostnameRegex)
        return predicate.evaluate(with: hostname) || isValidIPAddress(hostname)
    }
    
    private func isValidIPAddress(_ address: String) -> Bool {
        // Basic IP address validation
        let ipRegex = "^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", ipRegex)
        return predicate.evaluate(with: address)
    }
    
    private func testConnectionHealth(completion: @escaping (Bool) -> Void) {
        guard let connection = connection, connection.state == .ready else {
            completion(false)
            return
        }
        
        // Test the connection by sending a minimal keep-alive
        // If this fails, the connection has likely been reclaimed
        let testData = "\n".data(using: .utf8)!
        connection.send(content: testData, completion: .contentProcessed { error in
            DispatchQueue.main.async {
                completion(error == nil)
            }
        })
    }

    // Telnet option codes
    private let IAC: UInt8 = 255
    private let DO: UInt8 = 253
    private let WILL: UInt8 = 251
    private let SB: UInt8 = 250
    private let SE: UInt8 = 240
    private let TTYPE: UInt8 = 24
    private let SEND: UInt8 = 1
    private let IS: UInt8 = 0

    private func handleTelnetNegotiation(_ data: Data) -> Data {
        var i = 0
        var filteredData = Data()
        let bytes = [UInt8](data)
        while i < bytes.count {
            if bytes[i] == IAC {
                if i + 2 < bytes.count && bytes[i+1] == DO && bytes[i+2] == TTYPE {
                    // Respond to IAC DO TTYPE with IAC WILL TTYPE
                    let response: [UInt8] = [IAC, WILL, TTYPE]
                    print("[TTYPE] Responding to IAC DO TTYPE with IAC WILL TTYPE")
                    send(Data(response))
                    i += 3
                    continue
                } else if i + 5 < bytes.count && bytes[i+1] == SB && bytes[i+2] == TTYPE && bytes[i+3] == SEND && bytes[i+4] == IAC && bytes[i+5] == SE {
                    // Respond to IAC SB TTYPE SEND IAC SE with IAC SB TTYPE IS "xterm-256color" IAC SE
                    let ttypeString = "xterm-256color"
                    var response: [UInt8] = [IAC, SB, TTYPE, IS]
                    response.append(contentsOf: ttypeString.utf8)
                    response.append(contentsOf: [IAC, SE])
                    print("[TTYPE] Responding to TTYPE SEND with xterm-256color")
                    send(Data(response))
                    i += 6
                    continue
                }
            }
            filteredData.append(bytes[i])
            i += 1
        }
        return filteredData
    }
}

// MARK: - Error Types

enum MUDSocketError: Error, LocalizedError {
    case invalidHostname
    case invalidPort
    case connectionFailed
    case disconnected
    case networkUnavailable
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .invalidHostname:
            return "Invalid hostname. Please check the server address."
        case .invalidPort:
            return "Invalid port number. Port must be between 1 and 65535."
        case .connectionFailed:
            return "Failed to connect to the server. Please check your internet connection and server details."
        case .disconnected:
            return "Connection to the server was lost."
        case .networkUnavailable:
            return "Network is unavailable. Please check your internet connection."
        case .timeout:
            return "Connection timed out. The server may be unavailable."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidHostname:
            return "Verify the server hostname or IP address is correct."
        case .invalidPort:
            return "Check with the server administrator for the correct port number."
        case .connectionFailed:
            return "Try connecting again or contact the server administrator."
        case .disconnected:
            return "Try reconnecting to the server."
        case .networkUnavailable:
            return "Check your WiFi or cellular connection and try again."
        case .timeout:
            return "Wait a moment and try connecting again."
        }
    }
} 