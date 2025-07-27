import UIKit
import CoreData

class SessionDashboardViewController: UIViewController {
    
    // MARK: - Properties
    
    private var tableView: UITableView!
    private var refreshControl: UIRefreshControl!
    private var sessions: [SessionInfo] = []
    private weak var clientContainer: ClientContainer?
    
    // MARK: - Session Info Structure
    
    struct SessionInfo {
        let worldID: NSManagedObjectID
        let worldName: String
        let hostname: String
        let port: Int32
        let isConnected: Bool
        let isLogging: Bool
        let automationCount: Int
        let lastActivity: Date?
        let connectionDuration: TimeInterval?
    }
    
    // MARK: - Initialization
    
    init(clientContainer: ClientContainer? = nil) {
        self.clientContainer = clientContainer
        super.init(nibName: nil, bundle: nil)
        title = "📊 Session Dashboard"
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadSessions()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshSessions()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        setupNavigationBar()
        setupTableView()
        setupConstraints()
    }
    
    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
        
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                title: "Bulk Actions",
                style: .plain,
                target: self,
                action: #selector(bulkActionsButtonTapped)
            ),
            UIBarButtonItem(
                barButtonSystemItem: .refresh,
                target: self,
                action: #selector(refreshButtonTapped)
            )
        ]
        
        // Add segmented control for filtering
        let filterControl = UISegmentedControl(items: ["All", "Connected", "Active"])
        filterControl.selectedSegmentIndex = 0
        filterControl.addTarget(self, action: #selector(filterChanged(_:)), for: .valueChanged)
        navigationItem.titleView = filterControl
    }
    
    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        // Register custom cell
        tableView.register(SessionDashboardCell.self, forCellReuseIdentifier: "SessionDashboardCell")
        
        // Add refresh control
        refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshSessions), for: .valueChanged)
        tableView.refreshControl = refreshControl
        
        view.addSubview(tableView)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Data Loading
    
    private func loadSessions() {
        sessions.removeAll()
        
        let context = PersistenceController.shared.viewContext
        let request: NSFetchRequest<World> = World.fetchRequest()
        request.predicate = NSPredicate(format: "isHidden == NO")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \World.name, ascending: true)
        ]
        
        do {
            let worlds = try context.fetch(request)
            for world in worlds {
                let sessionInfo = createSessionInfo(from: world)
                sessions.append(sessionInfo)
            }
        } catch {
            print("Error loading worlds: \(error)")
        }
        
        tableView.reloadData()
    }
    
    private func createSessionInfo(from world: World) -> SessionInfo {
        // Get connection status from ClientContainer if available
        let isConnected = clientContainer?.isWorldConnected(world.objectID) ?? false
        
        // Calculate automation count
        let triggers = Array(world.triggers ?? []).filter { !$0.isHidden }.count
        let aliases = Array(world.aliases ?? []).filter { !$0.isHidden }.count
        let gags = Array(world.gags ?? []).filter { !$0.isHidden }.count
        let tickers = Array(world.tickers ?? []).filter { !$0.isHidden }.count
        let automationCount = triggers + aliases + gags + tickers
        
        // Check logging status (simplified - would need actual logger reference)
        let isLogging = UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoLogging)
        
        return SessionInfo(
            worldID: world.objectID,
            worldName: world.name ?? "Unknown World",
            hostname: world.hostname ?? "",
            port: world.port,
            isConnected: isConnected,
            isLogging: isLogging,
            automationCount: automationCount,
            lastActivity: world.lastModified,
            connectionDuration: nil // Would calculate from actual session data
        )
    }
    
    // MARK: - Actions
    
    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func refreshButtonTapped() {
        refreshSessions()
    }
    
    @objc private func refreshSessions() {
        loadSessions()
        refreshControl.endRefreshing()
    }
    
    @objc private func filterChanged(_ sender: UISegmentedControl) {
        // Apply filtering based on selected segment
        switch sender.selectedSegmentIndex {
        case 1: // Connected
            // Filter to show only connected sessions
            break
        case 2: // Active
            // Filter to show only sessions with recent activity
            break
        default: // All
            // Show all sessions
            break
        }
        loadSessions()
    }
    
    @objc private func bulkActionsButtonTapped() {
        let alert = UIAlertController(title: "Bulk Actions", message: "Choose an action to apply to all sessions", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "Connect All", style: .default) { [weak self] _ in
            self?.performBulkAction(.connectAll)
        })
        
        alert.addAction(UIAlertAction(title: "Disconnect All", style: .default) { [weak self] _ in
            self?.performBulkAction(.disconnectAll)
        })
        
        alert.addAction(UIAlertAction(title: "Start Logging All", style: .default) { [weak self] _ in
            self?.performBulkAction(.startLoggingAll)
        })
        
        alert.addAction(UIAlertAction(title: "Stop Logging All", style: .default) { [weak self] _ in
            self?.performBulkAction(.stopLoggingAll)
        })
        
        alert.addAction(UIAlertAction(title: "Export All Sessions", style: .default) { [weak self] _ in
            self?.performBulkAction(.exportAll)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        
        present(alert, animated: true)
    }
    
    // MARK: - Bulk Actions
    
    enum BulkAction {
        case connectAll
        case disconnectAll
        case startLoggingAll
        case stopLoggingAll
        case exportAll
    }
    
    private func performBulkAction(_ action: BulkAction) {
        switch action {
        case .connectAll:
            sessions.forEach { session in
                if !session.isConnected {
                    clientContainer?.connectToWorld(session.worldID)
                }
            }
            showAlert(title: "Connecting", message: "Connecting to all disconnected worlds...")
            
        case .disconnectAll:
            sessions.forEach { session in
                if session.isConnected {
                    clientContainer?.disconnectWorld(session.worldID)
                }
            }
            showAlert(title: "Disconnecting", message: "Disconnecting from all connected worlds...")
            
        case .startLoggingAll:
            // Implementation would start logging for all sessions
            showAlert(title: "Logging Started", message: "Session logging enabled for all worlds.")
            
        case .stopLoggingAll:
            // Implementation would stop logging for all sessions
            showAlert(title: "Logging Stopped", message: "Session logging disabled for all worlds.")
            
        case .exportAll:
            exportAllSessions()
        }
        
        // Refresh after bulk action
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.refreshSessions()
        }
    }
    
    private func exportAllSessions() {
        let exportData = generateExportData()
        
        let activityVC = UIActivityViewController(
            activityItems: [exportData],
            applicationActivities: nil
        )
        
        if let popover = activityVC.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        
        present(activityVC, animated: true)
    }
    
    private func generateExportData() -> String {
        var exportString = "MUDTapper Session Dashboard Export\n"
        exportString += "Generated: \(DateFormatter().string(from: Date()))\n\n"
        
        for session in sessions {
            exportString += "World: \(session.worldName)\n"
            exportString += "Host: \(session.hostname):\(session.port)\n"
            exportString += "Status: \(session.isConnected ? "Connected" : "Disconnected")\n"
            exportString += "Logging: \(session.isLogging ? "Active" : "Inactive")\n"
            exportString += "Automation Items: \(session.automationCount)\n"
            if let lastActivity = session.lastActivity {
                exportString += "Last Activity: \(DateFormatter().string(from: lastActivity))\n"
            }
            exportString += "\n"
        }
        
        return exportString
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension SessionDashboardViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sessions.isEmpty ? 1 : sessions.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if sessions.isEmpty {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "No worlds configured"
            cell.textLabel?.textColor = .secondaryLabel
            cell.selectionStyle = .none
            return cell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "SessionDashboardCell", for: indexPath) as! SessionDashboardCell
        let session = sessions[indexPath.row]
        cell.configure(with: session)
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Session Overview"
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        let connectedCount = sessions.filter { $0.isConnected }.count
        let loggingCount = sessions.filter { $0.isLogging }.count
        return "\(sessions.count) worlds • \(connectedCount) connected • \(loggingCount) logging"
    }
}

// MARK: - UITableViewDelegate

extension SessionDashboardViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard !sessions.isEmpty else { return }
        
        let session = sessions[indexPath.row]
        showSessionActions(for: session)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return sessions.isEmpty ? 44 : 80
    }
    
    private func showSessionActions(for session: SessionInfo) {
        let alert = UIAlertController(
            title: session.worldName,
            message: "\(session.hostname):\(session.port)",
            preferredStyle: .actionSheet
        )
        
        // Connection actions
        if session.isConnected {
            alert.addAction(UIAlertAction(title: "Disconnect", style: .default) { [weak self] _ in
                self?.clientContainer?.disconnectWorld(session.worldID)
                self?.refreshSessions()
            })
            
            alert.addAction(UIAlertAction(title: "Switch to Session", style: .default) { [weak self] _ in
                self?.clientContainer?.switchToWorld(session.worldID)
                self?.dismiss(animated: true)
            })
        } else {
            alert.addAction(UIAlertAction(title: "Connect", style: .default) { [weak self] _ in
                self?.clientContainer?.connectToWorld(session.worldID)
                self?.refreshSessions()
            })
        }
        
        // Logging actions
        let loggingTitle = session.isLogging ? "Stop Logging" : "Start Logging"
        alert.addAction(UIAlertAction(title: loggingTitle, style: .default) { [weak self] _ in
            // Toggle logging for this session
            self?.refreshSessions()
        })
        
        // Management actions
        alert.addAction(UIAlertAction(title: "Manage Automation", style: .default) { [weak self] _ in
            self?.showAutomationManagement(for: session)
        })
        
        alert.addAction(UIAlertAction(title: "View Logs", style: .default) { [weak self] _ in
            self?.showSessionLogs(for: session)
        })
        
        alert.addAction(UIAlertAction(title: "Export Session", style: .default) { [weak self] _ in
            self?.exportSession(session)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            if let cell = tableView.cellForRow(at: tableView.indexPath(for: session.worldID) ?? IndexPath(row: 0, section: 0)) {
                popover.sourceView = cell
                popover.sourceRect = cell.bounds
            }
        }
        
        present(alert, animated: true)
    }
    
    private func showAutomationManagement(for session: SessionInfo) {
        // Navigate to automation management for this world
        // Implementation would show automation settings for the specific world
        showAlert(title: "Automation Management", message: "Opening automation settings for \(session.worldName)...")
    }
    
    private func showSessionLogs(for session: SessionInfo) {
        // Navigate to log viewer for this session
        let logManagerVC = LogManagerViewController()
        let navController = UINavigationController(rootViewController: logManagerVC)
        navController.modalPresentationStyle = .pageSheet
        
        if #available(iOS 15.0, *) {
            if let sheet = navController.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        
        present(navController, animated: true)
    }
    
    private func exportSession(_ session: SessionInfo) {
        let exportData = """
        World: \(session.worldName)
        Host: \(session.hostname):\(session.port)
        Status: \(session.isConnected ? "Connected" : "Disconnected")
        Automation Items: \(session.automationCount)
        """
        
        let activityVC = UIActivityViewController(
            activityItems: [exportData],
            applicationActivities: nil
        )
        
        present(activityVC, animated: true)
    }
}

// MARK: - SessionDashboardCell

class SessionDashboardCell: UITableViewCell {
    
    private let worldNameLabel = UILabel()
    private let hostLabel = UILabel()
    private let statusStackView = UIStackView()
    private let connectionStatusView = UIView()
    private let loggingStatusView = UIView()
    private let automationCountLabel = UILabel()
    private let lastActivityLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        selectionStyle = .default
        
        // World name label
        worldNameLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        worldNameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Host label
        hostLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        hostLabel.textColor = .secondaryLabel
        hostLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Status indicators
        connectionStatusView.translatesAutoresizingMaskIntoConstraints = false
        connectionStatusView.layer.cornerRadius = 6
        connectionStatusView.widthAnchor.constraint(equalToConstant: 12).isActive = true
        connectionStatusView.heightAnchor.constraint(equalToConstant: 12).isActive = true
        
        loggingStatusView.translatesAutoresizingMaskIntoConstraints = false
        loggingStatusView.layer.cornerRadius = 6
        loggingStatusView.widthAnchor.constraint(equalToConstant: 12).isActive = true
        loggingStatusView.heightAnchor.constraint(equalToConstant: 12).isActive = true
        
        // Automation count
        automationCountLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        automationCountLabel.textColor = .systemBlue
        automationCountLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Last activity
        lastActivityLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        lastActivityLabel.textColor = .tertiaryLabel
        lastActivityLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Status stack view
        statusStackView.axis = .horizontal
        statusStackView.spacing = 8
        statusStackView.alignment = .center
        statusStackView.translatesAutoresizingMaskIntoConstraints = false
        statusStackView.addArrangedSubview(connectionStatusView)
        statusStackView.addArrangedSubview(loggingStatusView)
        statusStackView.addArrangedSubview(automationCountLabel)
        
        contentView.addSubview(worldNameLabel)
        contentView.addSubview(hostLabel)
        contentView.addSubview(statusStackView)
        contentView.addSubview(lastActivityLabel)
        
        NSLayoutConstraint.activate([
            worldNameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            worldNameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            worldNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusStackView.leadingAnchor, constant: -8),
            
            hostLabel.topAnchor.constraint(equalTo: worldNameLabel.bottomAnchor, constant: 4),
            hostLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            hostLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusStackView.leadingAnchor, constant: -8),
            
            statusStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            statusStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            lastActivityLabel.topAnchor.constraint(equalTo: hostLabel.bottomAnchor, constant: 4),
            lastActivityLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            lastActivityLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            lastActivityLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
    
    func configure(with session: SessionDashboardViewController.SessionInfo) {
        worldNameLabel.text = session.worldName
        hostLabel.text = "\(session.hostname):\(session.port)"
        
        // Connection status
        connectionStatusView.backgroundColor = session.isConnected ? .systemGreen : .systemRed
        
        // Logging status
        loggingStatusView.backgroundColor = session.isLogging ? .systemOrange : .systemGray4
        
        // Automation count
        if session.automationCount > 0 {
            automationCountLabel.text = "🤖 \(session.automationCount)"
            automationCountLabel.isHidden = false
        } else {
            automationCountLabel.isHidden = true
        }
        
        // Last activity
        if let lastActivity = session.lastActivity {
            let formatter = RelativeDateTimeFormatter()
            formatter.dateTimeStyle = .named
            lastActivityLabel.text = "Last: \(formatter.localizedString(for: lastActivity, relativeTo: Date()))"
        } else {
            lastActivityLabel.text = "Never connected"
        }
    }
}



// MARK: - UITableView Extension

extension UITableView {
    func indexPath(for worldID: NSManagedObjectID) -> IndexPath? {
        // Helper to find index path for a world ID
        // Implementation would depend on how the table view is structured
        return IndexPath(row: 0, section: 0) // Placeholder
    }
} 