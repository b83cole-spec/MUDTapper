import UIKit
import Foundation

class LogManagerViewController: UIViewController {
    
    // MARK: - Properties
    
    private var tableView: UITableView!
    private var searchBar: UISearchBar!
    private var logFiles: [URL] = []
    private var isSearching = false
    private var searchResults: [URL: [SessionLogger.SearchResult]] = [:]
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        loadLogFiles()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadLogFiles()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        title = "Session Logs"
        
        setupNavigationBar()
        setupSearchBar()
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
                title: "Clear All",
                style: .plain,
                target: self,
                action: #selector(clearAllButtonTapped)
            ),
            UIBarButtonItem(
                barButtonSystemItem: .action,
                target: self,
                action: #selector(exportAllButtonTapped)
            )
        ]
    }
    
    private func setupSearchBar() {
        searchBar = UISearchBar()
        searchBar.delegate = self
        searchBar.placeholder = "Search logs (text or regex)"
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)
    }
    
    private func setupTableView() {
        tableView = UITableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        tableView.separatorColor = ThemeManager.shared.linkColor.withAlphaComponent(0.3)
        
        // Register cells
        tableView.register(LogFileCell.self, forCellReuseIdentifier: "LogFileCell")
        tableView.register(SearchResultCell.self, forCellReuseIdentifier: "SearchResultCell")
        
        view.addSubview(tableView)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Data Loading
    
    private func loadLogFiles() {
        logFiles = SessionLogger.getAllLogFiles()
        
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    // MARK: - Actions
    
    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func clearAllButtonTapped() {
        let alert = UIAlertController(
            title: "Clear All Logs",
            message: "This will permanently delete all session log files. This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete All", style: .destructive) { _ in
            self.clearAllLogs()
        })
        
        present(alert, animated: true)
    }
    
    @objc private func exportAllButtonTapped() {
        guard !logFiles.isEmpty else {
            let alert = UIAlertController(title: "No Logs", message: "There are no log files to export.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        
        let alert = UIAlertController(
            title: "Export Logs",
            message: "Choose how to export your log files",
            preferredStyle: .actionSheet
        )
        
        alert.addAction(UIAlertAction(title: "Export All Files", style: .default) { _ in
            self.exportAllLogFiles()
        })
        
        alert.addAction(UIAlertAction(title: "Export as Combined File", style: .default) { _ in
            self.exportLogsAsCombined()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.last
        }
        
        present(alert, animated: true)
    }
    
    private func clearAllLogs() {
        var deletedCount = 0
        
        for logFile in logFiles {
            if SessionLogger.deleteLogFile(logFile) {
                deletedCount += 1
            }
        }
        
        loadLogFiles()
        
        let message = deletedCount > 0 ? 
            "Deleted \(deletedCount) log file(s)" : 
            "No log files were deleted"
        
        let alert = UIAlertController(title: "Logs Cleared", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func exportAllLogFiles() {
        let activityController = UIActivityViewController(activityItems: logFiles, applicationActivities: nil)
        activityController.setValue("MUDTapper Session Logs", forKey: "subject")
        
        // For iPad
        if let popover = activityController.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.last
        }
        
        present(activityController, animated: true)
    }
    
    private func exportLogsAsCombined() {
        DispatchQueue.global(qos: .userInitiated).async {
            let combinedURL = self.createCombinedLogFile()
            
            DispatchQueue.main.async {
                if let combinedURL = combinedURL {
                    let activityController = UIActivityViewController(activityItems: [combinedURL], applicationActivities: nil)
                    activityController.setValue("MUDTapper Combined Logs", forKey: "subject")
                    
                    // For iPad
                    if let popover = activityController.popoverPresentationController {
                        popover.barButtonItem = self.navigationItem.rightBarButtonItems?.last
                    }
                    
                    self.present(activityController, animated: true)
                } else {
                    let alert = UIAlertController(title: "Export Failed", message: "Could not create combined log file", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }
    
    private func createCombinedLogFile() -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = DateFormatter.filename.string(from: Date())
        
        // Create a combined text file instead of ZIP for simplicity
        let combinedURL = tempDir.appendingPathComponent("MUDTapper_Logs_Combined_\(timestamp).txt")
        
        do {
            var combinedContent = """
            =====================================
            MUDTapper Combined Log Export
            Generated: \(ISO8601DateFormatter().string(from: Date()))
            Total Files: \(logFiles.count)
            =====================================
            
            
            """
            
            for (index, logFile) in logFiles.enumerated() {
                let fileName = logFile.lastPathComponent
                combinedContent += """
                
                =====================================
                File \(index + 1) of \(logFiles.count): \(fileName)
                =====================================
                
                """
                
                if let fileContent = try? String(contentsOf: logFile, encoding: .utf8) {
                    combinedContent += fileContent
                } else {
                    combinedContent += "[Error: Could not read file content]\n"
                }
                
                combinedContent += "\n\n"
            }
            
            try combinedContent.write(to: combinedURL, atomically: true, encoding: .utf8)
            return combinedURL
            
        } catch {
            print("Failed to create combined log file: \(error)")
            return nil
        }
    }
    
    private func performSearch(_ query: String) {
        guard !query.isEmpty else {
            isSearching = false
            searchResults.removeAll()
            tableView.reloadData()
            return
        }
        
        isSearching = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Check if query looks like regex (contains regex special characters)
            let isRegex = query.contains("[") || query.contains("(") || query.contains("{") || 
                         query.contains("\\") || query.contains("^") || query.contains("$")
            
            let results = SessionLogger.searchLogs(
                query: query,
                caseSensitive: false,
                regex: isRegex,
                contextLines: 2
            )
            
            DispatchQueue.main.async {
                self.searchResults = results
                self.tableView.reloadData()
            }
        }
    }
}

// MARK: - UISearchBarDelegate

extension LogManagerViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        // Debounce search
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(delayedSearch), object: nil)
        perform(#selector(delayedSearch), with: nil, afterDelay: 0.5)
    }
    
    @objc private func delayedSearch() {
        performSearch(searchBar.text ?? "")
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        performSearch(searchBar.text ?? "")
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.resignFirstResponder()
        isSearching = false
        searchResults.removeAll()
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource

extension LogManagerViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return isSearching ? searchResults.count : 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isSearching {
            let files = Array(searchResults.keys).sorted { $0.lastPathComponent < $1.lastPathComponent }
            if section < files.count {
                return searchResults[files[section]]?.count ?? 0
            }
            return 0
        } else {
            return logFiles.count
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if isSearching {
            let files = Array(searchResults.keys).sorted { $0.lastPathComponent < $1.lastPathComponent }
            if section < files.count {
                let fileName = files[section].lastPathComponent
                let count = searchResults[files[section]]?.count ?? 0
                return "\(fileName) (\(count) matches)"
            }
        } else {
            return logFiles.isEmpty ? "No Session Logs" : "Session Log Files"
        }
        return nil
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if isSearching {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath) as! SearchResultCell
            
            let files = Array(searchResults.keys).sorted { $0.lastPathComponent < $1.lastPathComponent }
            if indexPath.section < files.count,
               let results = searchResults[files[indexPath.section]],
               indexPath.row < results.count {
                cell.configure(with: results[indexPath.row])
            }
            
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "LogFileCell", for: indexPath) as! LogFileCell
            
            if indexPath.row < logFiles.count {
                cell.configure(with: logFiles[indexPath.row])
            }
            
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension LogManagerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if isSearching {
            // Show search result in context
            let files = Array(searchResults.keys).sorted { $0.lastPathComponent < $1.lastPathComponent }
            if indexPath.section < files.count,
               let results = searchResults[files[indexPath.section]],
               indexPath.row < results.count {
                showLogContent(files[indexPath.section], highlightResult: results[indexPath.row])
            }
        } else {
            // Show full log file
            if indexPath.row < logFiles.count {
                showLogContent(logFiles[indexPath.row])
            }
        }
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete && !isSearching {
            if indexPath.row < logFiles.count {
                let fileToDelete = logFiles[indexPath.row]
                
                if SessionLogger.deleteLogFile(fileToDelete) {
                    logFiles.remove(at: indexPath.row)
                    tableView.deleteRows(at: [indexPath], with: .fade)
                } else {
                    let alert = UIAlertController(title: "Delete Failed", message: "Could not delete log file", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    present(alert, animated: true)
                }
            }
        }
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return !isSearching
    }
    
    private func showLogContent(_ fileURL: URL, highlightResult: SessionLogger.SearchResult? = nil) {
        let logViewController = LogContentViewController(fileURL: fileURL, highlightResult: highlightResult)
        let navController = UINavigationController(rootViewController: logViewController)
        navController.modalPresentationStyle = .pageSheet
        
        if #available(iOS 15.0, *) {
            if let sheet = navController.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        
        present(navController, animated: true)
    }
}

// MARK: - LogFileCell

class LogFileCell: UITableViewCell {
    
    private let fileNameLabel = UILabel()
    private let infoLabel = UILabel()
    private let dateLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        fileNameLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        fileNameLabel.textColor = ThemeManager.shared.terminalTextColor
        fileNameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        infoLabel.font = UIFont.systemFont(ofSize: 14)
        infoLabel.textColor = ThemeManager.shared.linkColor
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        
        dateLabel.font = UIFont.systemFont(ofSize: 12)
        dateLabel.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.7)
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(fileNameLabel)
        contentView.addSubview(infoLabel)
        contentView.addSubview(dateLabel)
        
        NSLayoutConstraint.activate([
            fileNameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            fileNameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            fileNameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            infoLabel.topAnchor.constraint(equalTo: fileNameLabel.bottomAnchor, constant: 4),
            infoLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            
            dateLabel.topAnchor.constraint(equalTo: fileNameLabel.bottomAnchor, constant: 4),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            dateLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    
    func configure(with fileURL: URL) {
        let fileName = fileURL.lastPathComponent
        fileNameLabel.text = fileName
        
        if let info = SessionLogger.getLogFileInfo(fileURL) {
            infoLabel.text = info.size
            dateLabel.text = info.date
        } else {
            infoLabel.text = "Unknown size"
            dateLabel.text = "Unknown date"
        }
    }
}

// MARK: - SearchResultCell

class SearchResultCell: UITableViewCell {
    
    private let lineNumberLabel = UILabel()
    private let contentLabel = UILabel()
    private let timestampLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        lineNumberLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        lineNumberLabel.textColor = ThemeManager.shared.linkColor
        lineNumberLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentLabel.font = ThemeManager.shared.terminalFont
        contentLabel.textColor = ThemeManager.shared.terminalTextColor
        contentLabel.numberOfLines = 0
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        
        timestampLabel.font = UIFont.systemFont(ofSize: 10)
        timestampLabel.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.7)
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(lineNumberLabel)
        contentView.addSubview(contentLabel)
        contentView.addSubview(timestampLabel)
        
        NSLayoutConstraint.activate([
            lineNumberLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            lineNumberLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            lineNumberLabel.widthAnchor.constraint(equalToConstant: 50),
            
            timestampLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            timestampLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            contentLabel.topAnchor.constraint(equalTo: lineNumberLabel.bottomAnchor, constant: 4),
            contentLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            contentLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            contentLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    
    func configure(with result: SessionLogger.SearchResult) {
        lineNumberLabel.text = "\(result.lineNumber)"
        contentLabel.text = result.line
        timestampLabel.text = result.timestamp ?? ""
    }
} 