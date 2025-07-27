import UIKit

class LogContentViewController: UIViewController {
    
    // MARK: - Properties
    
    private let fileURL: URL
    private let highlightResult: SessionLogger.SearchResult?
    private var textView: UITextView!
    private var searchBar: UISearchBar!
    private var isSearching = false
    private var currentSearchTerm = ""
    
    // MARK: - Initialization
    
    init(fileURL: URL, highlightResult: SessionLogger.SearchResult? = nil) {
        self.fileURL = fileURL
        self.highlightResult = highlightResult
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        loadLogContent()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // If we have a highlight result, scroll to it
        if let result = highlightResult {
            scrollToLine(result.lineNumber)
        }
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        title = fileURL.lastPathComponent
        
        setupNavigationBar()
        setupSearchBar()
        setupTextView()
        setupConstraints()
    }
    
    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(exportButtonTapped)
        )
    }
    
    private func setupSearchBar() {
        searchBar = UISearchBar()
        searchBar.delegate = self
        searchBar.placeholder = "Search in this log..."
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.isHidden = true
        view.addSubview(searchBar)
    }
    
    private func setupTextView() {
        textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        textView.textColor = ThemeManager.shared.terminalTextColor
        textView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = true
        textView.showsVerticalScrollIndicator = true
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        
        // Better text rendering
        textView.layoutManager.allowsNonContiguousLayout = false
        
        view.addSubview(textView)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            textView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Content Loading
    
    private func loadLogContent() {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            showError("Could not read log file")
            return
        }
        
        // Check file size and handle large files
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int64 ?? 0
        let maxSize: Int64 = 5 * 1024 * 1024 // 5MB limit for full loading
        
        if fileSize > maxSize {
            handleLargeLogFile(content: content, fileSize: fileSize)
        } else {
            displayFormattedContent(content)
        }
        
        // Highlight search result if provided
        if let result = highlightResult {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.highlightSearchResult(result)
            }
        }
    }
    
    private func handleLargeLogFile(content: String, fileSize: Int64) {
        let sizeMB = Double(fileSize) / (1024 * 1024)
        let alert = UIAlertController(
            title: "Large Log File",
            message: String(format: "This log file is %.1f MB. How would you like to view it?", sizeMB),
            preferredStyle: .actionSheet
        )
        
        alert.addAction(UIAlertAction(title: "Load Full File", style: .default) { _ in
            self.displayFormattedContent(content)
        })
        
        alert.addAction(UIAlertAction(title: "Load Last 1000 Lines", style: .default) { _ in
            let lines = content.components(separatedBy: .newlines)
            let lastLines = Array(lines.suffix(1000))
            let truncatedContent = "... (showing last 1000 lines of \(lines.count) total lines)\n\n" + lastLines.joined(separator: "\n")
            self.displayFormattedContent(truncatedContent)
        })
        
        alert.addAction(UIAlertAction(title: "Load First 1000 Lines", style: .default) { _ in
            let lines = content.components(separatedBy: .newlines)
            let firstLines = Array(lines.prefix(1000))
            let truncatedContent = firstLines.joined(separator: "\n") + "\n\n... (showing first 1000 lines of \(lines.count) total lines)"
            self.displayFormattedContent(truncatedContent)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            self.dismiss(animated: true)
        })
        
        present(alert, animated: true)
    }
    
    private func displayFormattedContent(_ content: String) {
        let attributedText = NSMutableAttributedString()
        
        // First, try to fix concatenated timestamps by splitting on timestamp patterns
        let fixedContent = fixConcatenatedTimestamps(content)
        let lines = fixedContent.components(separatedBy: .newlines)
        
        // Create paragraph style with better line spacing
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2.0
        paragraphStyle.paragraphSpacing = 4.0
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip completely empty lines but preserve intentional spacing
            if !trimmedLine.isEmpty {
                let formattedLine = formatLogLine(trimmedLine, paragraphStyle: paragraphStyle)
                attributedText.append(formattedLine)
                
                // Add a newline after each line (except the last one)
                if index < lines.count - 1 {
                    let newlineAttributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                        .paragraphStyle: paragraphStyle
                    ]
                    attributedText.append(NSAttributedString(string: "\n", attributes: newlineAttributes))
                }
            }
        }
        
        textView.attributedText = attributedText
    }
    
    private func fixConcatenatedTimestamps(_ content: String) -> String {
        // Pattern to match timestamp format: [YYYY-MM-DD HH:MM:SS]
        let timestampPattern = #"\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]"#
        
        do {
            let regex = try NSRegularExpression(pattern: timestampPattern, options: [])
            let range = NSRange(location: 0, length: content.utf16.count)
            
            // Find all timestamp matches
            let matches = regex.matches(in: content, options: [], range: range)
            
            // Work backwards to avoid index shifting issues
            var fixedContent = content
            for match in matches.reversed() {
                // Skip the first match (beginning of content)
                if match.range.location > 0 {
                    // Check if there's no newline before this timestamp
                    let beforeIndex = match.range.location - 1
                    let beforeRange = NSRange(location: beforeIndex, length: 1)
                    
                    if beforeRange.location >= 0 && beforeRange.location < fixedContent.utf16.count {
                        let beforeChar = String(fixedContent[Range(beforeRange, in: fixedContent)!])
                        if beforeChar != "\n" {
                            // Insert a newline before this timestamp
                            let insertIndex = fixedContent.index(fixedContent.startIndex, offsetBy: match.range.location)
                            fixedContent.insert("\n", at: insertIndex)
                        }
                    }
                }
            }
            
            return fixedContent
        } catch {
            // If regex fails, return original content
            return content
        }
    }
    
    private func formatLogLine(_ line: String, paragraphStyle: NSParagraphStyle) -> NSAttributedString {
        let attributedString = NSMutableAttributedString()
        
        // Base font and color
        let baseFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let baseColor = ThemeManager.shared.terminalTextColor
        
        // Base attributes with paragraph style
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: baseColor,
            .paragraphStyle: paragraphStyle
        ]
        
        // Check for different line types
        if line.hasPrefix("=====") {
            // Header/footer lines - make them stand out more
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .bold),
                .foregroundColor: ThemeManager.shared.linkColor,
                .paragraphStyle: paragraphStyle,
                .backgroundColor: ThemeManager.shared.linkColor.withAlphaComponent(0.1)
            ]
            attributedString.append(NSAttributedString(string: line, attributes: headerAttributes))
        } else if line.contains("] >") {
            // Command lines (outgoing) - split timestamp and command
            if let range = line.range(of: "] >") {
                let timestampPart = String(line[..<range.upperBound])
                let commandPart = String(line[range.upperBound...])
                
                // Timestamp in muted color
                let timestampAttributes: [NSAttributedString.Key: Any] = [
                    .font: baseFont,
                    .foregroundColor: baseColor.withAlphaComponent(0.6),
                    .paragraphStyle: paragraphStyle
                ]
                attributedString.append(NSAttributedString(string: timestampPart, attributes: timestampAttributes))
                
                // Command in green with slight background
                let commandAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .medium),
                    .foregroundColor: UIColor.systemGreen,
                    .paragraphStyle: paragraphStyle,
                    .backgroundColor: UIColor.systemGreen.withAlphaComponent(0.05)
                ]
                attributedString.append(NSAttributedString(string: commandPart, attributes: commandAttributes))
            } else {
                attributedString.append(NSAttributedString(string: line, attributes: baseAttributes))
            }
        } else if line.hasPrefix("[") && line.contains("]") {
            // Regular timestamped lines - split timestamp and content
            if let range = line.range(of: "]") {
                let timestampPart = String(line[...range.upperBound])
                let contentPart = String(line[range.upperBound...])
                
                // Timestamp in muted color
                let timestampAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: baseColor.withAlphaComponent(0.5),
                    .paragraphStyle: paragraphStyle
                ]
                attributedString.append(NSAttributedString(string: timestampPart, attributes: timestampAttributes))
                
                // Content in normal color
                let contentAttributes: [NSAttributedString.Key: Any] = [
                    .font: baseFont,
                    .foregroundColor: baseColor,
                    .paragraphStyle: paragraphStyle
                ]
                attributedString.append(NSAttributedString(string: contentPart, attributes: contentAttributes))
            } else {
                attributedString.append(NSAttributedString(string: line, attributes: baseAttributes))
            }
        } else if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Empty lines - add some visual space
            let emptyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 8, weight: .regular),
                .paragraphStyle: paragraphStyle
            ]
            attributedString.append(NSAttributedString(string: " ", attributes: emptyAttributes))
        } else {
            // Plain lines
            attributedString.append(NSAttributedString(string: line, attributes: baseAttributes))
        }
        
        return attributedString
    }
    
    private func highlightSearchResult(_ result: SessionLogger.SearchResult) {
        guard let text = textView.attributedText?.mutableCopy() as? NSMutableAttributedString else { return }
        
        // Find the line in the text
        let lines = text.string.components(separatedBy: .newlines)
        
        // Convert line number to character range
        if result.lineNumber > 0 && result.lineNumber <= lines.count {
            let targetLineIndex = result.lineNumber - 1
            var characterIndex = 0
            
            for i in 0..<targetLineIndex {
                characterIndex += lines[i].count + 1 // +1 for newline
            }
            
            let lineLength = lines[targetLineIndex].count
            let lineRange = NSRange(location: characterIndex, length: lineLength)
            
            // Highlight the entire line
            text.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.3), range: lineRange)
            
            textView.attributedText = text
        }
    }
    
    private func scrollToLine(_ lineNumber: Int) {
        guard let text = textView.text else { return }
        
        let lines = text.components(separatedBy: .newlines)
        
        if lineNumber > 0 && lineNumber <= lines.count {
            let targetLineIndex = lineNumber - 1
            var characterIndex = 0
            
            for i in 0..<targetLineIndex {
                characterIndex += lines[i].count + 1 // +1 for newline
            }
            
            let targetRange = NSRange(location: characterIndex, length: 0)
            textView.scrollRangeToVisible(targetRange)
        }
    }
    
    private func showError(_ message: String) {
        textView.text = "Error loading log file:\n\n\(message)"
        textView.textColor = .systemRed
    }
    
    // MARK: - Actions
    
    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func exportButtonTapped() {
        let fileName = fileURL.lastPathComponent
        let activityController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        
        // Set subject for email sharing
        activityController.setValue("MUDTapper Log: \(fileName)", forKey: "subject")
        
        // For iPad
        if let popover = activityController.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(activityController, animated: true)
    }
    
    @objc private func searchButtonTapped() {
        isSearching = !isSearching
        searchBar.isHidden = !isSearching
        
        if isSearching {
            searchBar.becomeFirstResponder()
        } else {
            searchBar.resignFirstResponder()
            clearSearch()
        }
        
        // Update layout
        view.setNeedsLayout()
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        }
    }
    
    private func performSearch(_ query: String) {
        guard let text = textView.attributedText?.mutableCopy() as? NSMutableAttributedString else { return }
        
        currentSearchTerm = query
        
        // Reset any previous highlights
        let fullRange = NSRange(location: 0, length: text.length)
        text.removeAttribute(.backgroundColor, range: fullRange)
        
        if !query.isEmpty {
            // Search for occurrences
            let searchString = text.string.lowercased()
            let searchQuery = query.lowercased()
            
            var searchRange = NSRange(location: 0, length: searchString.count)
            var matches: [NSRange] = []
            
            while searchRange.location < searchString.count {
                let foundRange = (searchString as NSString).range(of: searchQuery, options: [], range: searchRange)
                if foundRange.location == NSNotFound {
                    break
                }
                
                matches.append(foundRange)
                searchRange = NSRange(location: foundRange.location + foundRange.length, 
                                    length: searchString.count - (foundRange.location + foundRange.length))
            }
            
            // Highlight matches
            for match in matches {
                text.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.5), range: match)
            }
            
            // Scroll to first match
            if let firstMatch = matches.first {
                textView.scrollRangeToVisible(firstMatch)
            }
        }
        
        textView.attributedText = text
    }
    
    private func clearSearch() {
        guard let text = textView.attributedText?.mutableCopy() as? NSMutableAttributedString else { return }
        
        let fullRange = NSRange(location: 0, length: text.length)
        text.removeAttribute(.backgroundColor, range: fullRange)
        
        // Re-highlight search result if we have one
        if let result = highlightResult {
            highlightSearchResult(result)
        }
        
        textView.attributedText = text
        currentSearchTerm = ""
    }
}

// MARK: - UISearchBarDelegate

extension LogContentViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        performSearch(searchText)
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.resignFirstResponder()
        clearSearch()
        isSearching = false
        searchBar.isHidden = true
        
        view.setNeedsLayout()
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        }
    }
} 