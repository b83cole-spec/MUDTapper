import UIKit

protocol InputToolbarDelegate: AnyObject {
    func inputToolbar(_ toolbar: InputToolbar, didSendText text: String)
}

class InputToolbar: UIView {
    
    // MARK: - Properties
    
    weak var delegate: InputToolbarDelegate?
    
    private var textField: UITextField!
    private var sendButton: UIButton!
    private var backgroundView: UIView!
    private var upButton: UIButton!
    private var downButton: UIButton!
    private let themeManager: ThemeManager
    
    // Public getter for textField
    var inputTextField: UITextField? {
        return textField
    }
    
    // Command history
    private var commandHistory: [String] = []
    private var historyIndex: Int = -1
    private var currentInput: String = ""
    private let maxHistorySize = 100
    
    // MARK: - Initialization
    
    init(themeManager: ThemeManager) {
        self.themeManager = themeManager
        super.init(frame: .zero)
        setupUI()
        loadCommandHistory()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported for InputToolbar; use init(themeManager:)")
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        backgroundColor = .clear
        
        // Background view
        backgroundView = UIView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = themeManager.terminalBackgroundColor
        backgroundView.layer.borderWidth = 1
        backgroundView.layer.borderColor = themeManager.terminalTextColor.withAlphaComponent(0.3).cgColor
        addSubview(backgroundView)
        
        // Text field
        textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.backgroundColor = .clear
        textField.font = themeManager.terminalFont
        textField.textColor = themeManager.terminalTextColor
        textField.placeholder = "Enter command..."
        textField.returnKeyType = .send
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.delegate = self
        
        // Optimize for faster keyboard response
        textField.enablesReturnKeyAutomatically = false
        textField.clearButtonMode = .never
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.smartInsertDeleteType = .no
        
        // Accessibility
        textField.accessibilityLabel = "Command Input"
        textField.accessibilityHint = "Enter MUD commands here. Swipe up or down to navigate command history."
        
        // Set placeholder color
        if let placeholder = textField.placeholder {
            textField.attributedPlaceholder = NSAttributedString(
                string: placeholder,
                attributes: [.foregroundColor: themeManager.terminalTextColor.withAlphaComponent(0.5)]
            )
        }
        
        backgroundView.addSubview(textField)
        
        // History navigation buttons
        upButton = UIButton(type: .system)
        upButton.translatesAutoresizingMaskIntoConstraints = false
        upButton.setImage(UIImage(systemName: "chevron.up"), for: .normal)
        upButton.tintColor = themeManager.linkColor
        upButton.addTarget(self, action: #selector(upButtonTapped), for: .touchUpInside)
        upButton.accessibilityLabel = "Previous Command"
        upButton.accessibilityHint = "Navigate to previous command in history"
        backgroundView.addSubview(upButton)
        
        downButton = UIButton(type: .system)
        downButton.translatesAutoresizingMaskIntoConstraints = false
        downButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        downButton.tintColor = themeManager.linkColor
        downButton.addTarget(self, action: #selector(downButtonTapped), for: .touchUpInside)
        downButton.accessibilityLabel = "Next Command"
        downButton.accessibilityHint = "Navigate to next command in history"
        backgroundView.addSubview(downButton)
        
        // Send button
        sendButton = UIButton(type: .system)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setImage(UIImage(systemName: "return"), for: .normal)
        sendButton.tintColor = themeManager.linkColor
        sendButton.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)
        sendButton.accessibilityLabel = "Send Command"
        sendButton.accessibilityHint = "Send the entered command to the MUD server"
        backgroundView.addSubview(sendButton)
        
        // Setup constraints
        let backgroundConstraints = [
            // Background view
            backgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0),
            backgroundView.heightAnchor.constraint(equalToConstant: 44)
        ]
        
        let sendButtonConstraints = [
            // Send button (reduced width since it's now an icon)
            sendButton.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 30),
            sendButton.heightAnchor.constraint(equalToConstant: 30)
        ]
        
        let navigationButtonConstraints = [
            // Down button (reduced spacing by 20%: 8 -> 6.4)
            downButton.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -6),
            downButton.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            downButton.widthAnchor.constraint(equalToConstant: 30),
            downButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Up button (reduced spacing by 20%: 4 -> 3.2)
            upButton.trailingAnchor.constraint(equalTo: downButton.leadingAnchor, constant: -3),
            upButton.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            upButton.widthAnchor.constraint(equalToConstant: 30),
            upButton.heightAnchor.constraint(equalToConstant: 30)
        ]
        
        let textFieldConstraints = [
            // Text field
            textField.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 12),
            textField.trailingAnchor.constraint(equalTo: upButton.leadingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor)
        ]
        
        // Set priorities to prevent conflicts
        backgroundConstraints.forEach { $0.priority = UILayoutPriority(999) }
        
        NSLayoutConstraint.activate(backgroundConstraints + sendButtonConstraints + navigationButtonConstraints + textFieldConstraints)
        
        // Add swipe gestures for history navigation
        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(swipeUp))
        swipeUp.direction = .up
        textField.addGestureRecognizer(swipeUp)
        
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(swipeDown))
        swipeDown.direction = .down
        textField.addGestureRecognizer(swipeDown)
        
        // Add tap gesture to background for immediate keyboard activation
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        backgroundView.addGestureRecognizer(tapGesture)
        
        // Update button states
        updateHistoryButtonStates()
        
        // Setup number bar
        setupNumberBar()
        
        // Setup notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeChanged),
            name: .themeDidChange,
            object: nil
        )
    }
    
    // MARK: - Command History Management
    
    private func loadCommandHistory() {
        if let savedHistory = UserDefaults.standard.array(forKey: "CommandHistory") as? [String] {
            commandHistory = savedHistory
        }
    }
    
    private func saveCommandHistory() {
        UserDefaults.standard.set(commandHistory, forKey: "CommandHistory")
    }
    
    private func addToHistory(_ command: String) {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Don't add empty commands or duplicates of the most recent command
        guard !trimmedCommand.isEmpty,
              commandHistory.last != trimmedCommand else {
            return
        }
        
        // Remove any existing instance of this command
        commandHistory.removeAll { $0 == trimmedCommand }
        
        // Add to end of history
        commandHistory.append(trimmedCommand)
        
        // Limit history size
        if commandHistory.count > maxHistorySize {
            commandHistory.removeFirst(commandHistory.count - maxHistorySize)
        }
        
        // Reset history navigation
        historyIndex = -1
        currentInput = ""
        
        // Save to UserDefaults
        saveCommandHistory()
        
        // Update button states
        updateHistoryButtonStates()
    }
    
    private func navigateHistory(direction: Int) {
        // Save current input if we're starting to navigate
        if historyIndex == -1 {
            currentInput = textField.text ?? ""
        }
        
        let newIndex = historyIndex + direction
        
        if newIndex >= 0 && newIndex < commandHistory.count {
            // Navigate within history
            historyIndex = newIndex
            textField.text = commandHistory[commandHistory.count - 1 - historyIndex]
        } else if newIndex == -1 {
            // Return to current input
            historyIndex = -1
            textField.text = currentInput
        }
        
        // Move cursor to end
        textField.selectedTextRange = textField.textRange(from: textField.endOfDocument, to: textField.endOfDocument)
        
        updateHistoryButtonStates()
    }
    
    private func updateHistoryButtonStates() {
        let hasHistory = !commandHistory.isEmpty
        let canGoUp = hasHistory && (historyIndex < commandHistory.count - 1)
        let canGoDown = historyIndex > -1
        
        upButton.isEnabled = canGoUp
        downButton.isEnabled = canGoDown
        
        upButton.alpha = canGoUp ? 1.0 : 0.3
        downButton.alpha = canGoDown ? 1.0 : 0.3
    }
    
    // MARK: - Public Methods
    
    func applyTheme() {
        backgroundView.backgroundColor = themeManager.terminalBackgroundColor
        backgroundView.layer.borderColor = themeManager.terminalTextColor.withAlphaComponent(0.3).cgColor
        
        textField.font = themeManager.terminalFont
        textField.textColor = themeManager.terminalTextColor
        
        if let placeholder = textField.placeholder {
            textField.attributedPlaceholder = NSAttributedString(
                string: placeholder,
                attributes: [.foregroundColor: themeManager.terminalTextColor.withAlphaComponent(0.5)]
            )
        }
        
        sendButton.tintColor = themeManager.linkColor
        
        upButton.tintColor = themeManager.linkColor
        downButton.tintColor = themeManager.linkColor
    }
    
    override func resignFirstResponder() -> Bool {
        return textField.resignFirstResponder()
    }
    
    override func becomeFirstResponder() -> Bool {
        return textField.becomeFirstResponder()
    }
    
    func clearHistory() {
        commandHistory.removeAll()
        historyIndex = -1
        currentInput = ""
        saveCommandHistory()
        updateHistoryButtonStates()
    }
    
    // MARK: - Number Bar Setup
    
    private func setupNumberBar() {
        // Create number bar as input accessory view
        let numberBar = createNumberBarView()
        textField.inputAccessoryView = numberBar
    }
    
    private func createNumberBarView() -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = UIColor.systemBackground
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Create scroll view for numbers
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(scrollView)
        
        // Create stack view for buttons
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)
        
        // Add number and punctuation buttons
        let characters = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "\u{0027}", "\u{0022}", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "-", "_", "=", "+", "[", "]", "{", "}", "\\", "|", ";", ":", ",", ".", "<", ">", "/", "?"]
        for character in characters {
            let button = UIButton(type: .system)
            button.setTitle(character, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
            button.backgroundColor = UIColor.systemGray6
            button.layer.cornerRadius = 6
            button.setTitleColor(.systemBlue, for: .normal)
            button.addTarget(self, action: #selector(numberButtonTapped(_:)), for: .touchUpInside)
            
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            
            stackView.addArrangedSubview(button)
        }
        
        // Setup constraints
        NSLayoutConstraint.activate([
            containerView.heightAnchor.constraint(equalToConstant: 44),
            
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -4),
            
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
        
        return containerView
    }
    
    @objc private func numberButtonTapped(_ sender: UIButton) {
        guard let title = sender.title(for: .normal) else { return }
        textField.insertText(title)
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    func showNumberBar() {
        // Number bar is automatically shown as inputAccessoryView when keyboard appears
    }
    
    func hideNumberBar() {
        // Number bar is automatically hidden when keyboard disappears
    }
    
    func insertText(_ text: String) {
        textField.insertText(text)
    }
    
    // MARK: - Actions
    
    @objc private func sendButtonTapped() {
        sendText()
    }
    
    @objc private func upButtonTapped() {
        navigateHistory(direction: 1)
    }
    
    @objc private func downButtonTapped() {
        navigateHistory(direction: -1)
    }
    
    @objc private func swipeUp() {
        navigateHistory(direction: 1)
    }
    
    @objc private func swipeDown() {
        navigateHistory(direction: -1)
    }
    
    @objc private func backgroundTapped() {
        // Immediately focus the text field for faster keyboard response
        textField.becomeFirstResponder()
    }
    
    @objc private func themeChanged() {
        DispatchQueue.main.async {
            self.applyTheme()
        }
    }
    
    // MARK: - Private Methods
    
    private func sendText() {
        guard let raw = textField.text else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Immediate UI feedback - disable send button briefly to prevent double-sends
        sendButton.isEnabled = false
        
        // Add to history only if non-empty
        if !text.isEmpty {
            addToHistory(text)
        }
        
        // Send immediately on main queue for best responsiveness (even if empty -> sends CRLF)
        delegate?.inputToolbar(self, didSendText: text)
        
        // Reset history navigation but keep the current command visible
        historyIndex = -1
        currentInput = text
        updateHistoryButtonStates()
        
        // Select all text so user can easily type a new command if they want
        textField.selectAll(nil)
        
        // Re-enable send button after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.sendButton.isEnabled = true
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - UITextFieldDelegate

extension InputToolbar: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendText()
        return true
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        // Scroll to show input when keyboard appears if needed
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        // Handle end editing if needed
    }
    
    func textFieldDidChangeSelection(_ textField: UITextField) {
        // Update button states when text changes
        updateHistoryButtonStates()
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // If user starts typing and we're not actively navigating history,
        // and the text is currently selected (from the previous command),
        // reset the history navigation state
        if historyIndex == -1 && textField.selectedTextRange != nil {
            let selectedRange = textField.selectedTextRange
            let startPosition = textField.beginningOfDocument
            let endPosition = textField.endOfDocument
            
            // Check if all text is selected
            if let selectedRange = selectedRange,
               textField.compare(selectedRange.start, to: startPosition) == .orderedSame &&
               textField.compare(selectedRange.end, to: endPosition) == .orderedSame {
                // All text is selected, so user is starting to type a new command
                currentInput = ""
            }
        }
        
        return true
    }
} 