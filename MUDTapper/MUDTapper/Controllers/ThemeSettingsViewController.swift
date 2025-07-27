import UIKit
import ObjectiveC

class ThemeSettingsViewController: SettingsViewController {
    
    // MARK: - Properties
    
    private var themeManager: ThemeManager
    
    // MARK: - Initialization
    
    init(themeManager: ThemeManager = ThemeManager.shared) {
        self.themeManager = themeManager
        super.init(title: "🎨 Themes & Appearance")
    }
    
    required init?(coder: NSCoder) {
        self.themeManager = ThemeManager.shared
        super.init(coder: coder)
    }
    
    // MARK: - Setup
    
    override func setupSections() {
        let sections: [SettingsSection] = [
            createThemeSection(),
            createFontSection(),
            createDisplaySection(),
            createColorSection()
        ]
        
        setSections(sections)
    }
    
    // MARK: - Section Creation
    
    private func createThemeSection() -> SettingsSection {
        let items: [SettingsItem] = [
            NavigationSettingsItem(
                title: "Theme Selection",
                detail: themeManager.currentTheme.name,
                accessibilityHint: "Choose from available color themes"
            ) { [weak self] in
                ThemeSelectionViewController(themeManager: self?.themeManager ?? ThemeManager.shared)
            },
            ActionSettingsItem(
                title: "Create Custom Theme",
                accessibilityHint: "Design your own color theme"
            ) { [weak self] in
                self?.createCustomTheme()
            },
            NavigationSettingsItem(
                title: "Manage Themes",
                accessibilityHint: "Edit, duplicate, or delete custom themes"
            ) { [weak self] in
                ThemeManagementViewController(themeManager: self?.themeManager ?? ThemeManager.shared)
            }
        ]
        
        return SettingsSection(
            title: "Color Themes",
            footer: "Choose or create color schemes for your terminal",
            items: items
        )
    }
    
    private func createFontSection() -> SettingsSection {
        let items: [SettingsItem] = [
            NavigationSettingsItem(
                title: "Font Family",
                detail: themeManager.currentTheme.fontName,
                accessibilityHint: "Choose terminal font family"
            ) { [weak self] in
                FontSelectionViewController(themeManager: self?.themeManager ?? ThemeManager.shared)
            },
            ActionSettingsItem(
                title: "Font Size",
                accessibilityHint: "Adjust text size"
            ) { [weak self] in
                self?.showFontSizeSelector()
            },
            ToggleSettingsItem(
                title: "Bold Text",
                accessibilityHint: "Use bold weight for all text",
                userDefaultsKey: UserDefaultsKeys.useBoldText,
                onToggle: { [weak self] _ in
                    self?.themeManager.refreshTheme()
                }
            ),
            ToggleSettingsItem(
                title: "Dynamic Type",
                accessibilityHint: "Respect system text size settings",
                userDefaultsKey: UserDefaultsKeys.useDynamicType,
                defaultValue: true,
                onToggle: { [weak self] _ in
                    self?.themeManager.refreshTheme()
                }
            )
        ]
        
        return SettingsSection(
            title: "Typography",
            footer: "Customize text appearance and readability",
            items: items
        )
    }
    
    private func createDisplaySection() -> SettingsSection {
        let items: [SettingsItem] = [
            ToggleSettingsItem(
                title: "Follow System Appearance",
                accessibilityHint: "Automatically switch between light and dark themes",
                userDefaultsKey: UserDefaultsKeys.followSystemAppearance,
                defaultValue: true,
                onToggle: { [weak self] enabled in
                    if enabled {
                        self?.themeManager.updateForSystemAppearance()
                    }
                }
            ),
            ToggleSettingsItem(
                title: "High Contrast",
                accessibilityHint: "Increase contrast for better visibility",
                userDefaultsKey: UserDefaultsKeys.useHighContrast,
                onToggle: { [weak self] _ in
                    self?.themeManager.refreshTheme()
                }
            ),
            ToggleSettingsItem(
                title: "Reduce Motion",
                accessibilityHint: "Minimize animations and transitions",
                userDefaultsKey: UserDefaultsKeys.reduceMotion
            ),
            ActionSettingsItem(
                title: "Line Spacing",
                accessibilityHint: "Adjust space between lines of text"
            ) { [weak self] in
                self?.showLineSpacingSelector()
            }
        ]
        
        return SettingsSection(
            title: "Display Options",
            footer: "Configure visual accessibility and preferences",
            items: items
        )
    }
    
    private func createColorSection() -> SettingsSection {
        let items: [SettingsItem] = [
            ToggleSettingsItem(
                title: "ANSI Colors",
                accessibilityHint: "Enable full spectrum terminal colors",
                userDefaultsKey: UserDefaultsKeys.enableANSIColors,
                defaultValue: true,
                onToggle: { [weak self] _ in
                    self?.themeManager.refreshTheme()
                }
            ),
            ToggleSettingsItem(
                title: "256 Color Mode",
                accessibilityHint: "Support extended color palette",
                userDefaultsKey: UserDefaultsKeys.enable256Colors,
                defaultValue: true,
                onToggle: { [weak self] _ in
                    self?.themeManager.refreshTheme()
                }
            ),
            ToggleSettingsItem(
                title: "True Color (24-bit)",
                accessibilityHint: "Enable millions of colors",
                userDefaultsKey: UserDefaultsKeys.enableTrueColor,
                defaultValue: false,
                onToggle: { [weak self] _ in
                    self?.themeManager.refreshTheme()
                }
            ),
            ActionSettingsItem(
                title: "Color Preview",
                accessibilityHint: "Test color display and ANSI sequences"
            ) { [weak self] in
                self?.showColorPreview()
            }
        ]
        
        return SettingsSection(
            title: "Color Support",
            footer: "Configure terminal color capabilities",
            items: items
        )
    }
    
    // MARK: - Action Methods
    
    private func createCustomTheme() {
        let customThemeVC = CustomThemeCreatorViewController(themeManager: themeManager)
        let navController = UINavigationController(rootViewController: customThemeVC)
        navController.modalPresentationStyle = .pageSheet
        
        if #available(iOS 15.0, *) {
            if let sheet = navController.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
            }
        }
        
        present(navController, animated: true)
    }
    
    private func showFontSizeSelector() {
        let alert = UIAlertController(
            title: "Font Size",
            message: "Select text size (8-24 points)",
            preferredStyle: .alert
        )
        
        alert.addTextField { [weak self] textField in
            textField.placeholder = "Font size"
            textField.keyboardType = .numberPad
            textField.text = "\(Int(self?.themeManager.currentTheme.fontSize ?? 14))"
        }
        
        alert.addAction(UIAlertAction(title: "Set", style: .default) { [weak self] _ in
            guard let text = alert.textFields?.first?.text,
                  let size = Int(text),
                  size >= 8 && size <= 24 else {
                self?.showAlert(title: "Invalid Size", message: "Please enter a size between 8 and 24 points.")
                return
            }
            
            self?.themeManager.setFontSize(CGFloat(size))
            self?.showAlert(title: "Font Size Updated", message: "Text size set to \(size) points.")
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showLineSpacingSelector() {
        let alert = UIAlertController(
            title: "Line Spacing",
            message: "Adjust space between lines (1.0-2.0)",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Line spacing"
            textField.keyboardType = .decimalPad
            let currentSpacing = UserDefaults.standard.double(forKey: UserDefaultsKeys.lineSpacing)
            textField.text = currentSpacing > 0 ? "\(currentSpacing)" : "1.2"
        }
        
        alert.addAction(UIAlertAction(title: "Set", style: .default) { [weak self] _ in
            guard let text = alert.textFields?.first?.text,
                  let spacing = Double(text),
                  spacing >= 1.0 && spacing <= 2.0 else {
                self?.showAlert(title: "Invalid Spacing", message: "Please enter a value between 1.0 and 2.0.")
                return
            }
            
            UserDefaults.standard.set(spacing, forKey: UserDefaultsKeys.lineSpacing)
            self?.themeManager.refreshTheme()
            self?.showAlert(title: "Line Spacing Updated", message: "Line spacing set to \(spacing).")
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showColorPreview() {
        // Create a sample theme for preview based on current theme
        let sampleTheme = CustomTheme(
            name: "Preview",
            terminalBackground: themeManager.currentTheme.backgroundColor,
            interfaceBackground: themeManager.currentTheme.backgroundColor,
            foregroundColor: themeManager.currentTheme.fontColor,
            linkColor: themeManager.currentTheme.linkColor,
            inputTextColor: themeManager.currentTheme.fontColor
        )
        let previewVC = ThemePreviewViewController(theme: sampleTheme)
        let navController = UINavigationController(rootViewController: previewVC)
        navController.modalPresentationStyle = UIModalPresentationStyle.pageSheet
        
        if #available(iOS 15.0, *) {
            if let sheet = navController.sheetPresentationController {
                sheet.prefersGrabberVisible = true
            }
        }
        
        present(navController, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Theme Selection View Controller

class ThemeSelectionViewController: UIViewController {
    
    private var tableView: UITableView!
    private var themeManager: ThemeManager
    private var availableThemes: [MUDTheme] = []
    
    init(themeManager: ThemeManager) {
        self.themeManager = themeManager
        super.init(nibName: nil, bundle: nil)
        title = "Select Theme"
        loadAvailableThemes()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = themeManager.terminalBackgroundColor
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
        
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = themeManager.terminalBackgroundColor
        tableView.register(ThemePreviewCell.self, forCellReuseIdentifier: "ThemePreviewCell")
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func loadAvailableThemes() {
        // Load built-in and custom themes
        availableThemes = themeManager.allAvailableThemes()
    }
    
    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }
}

extension ThemeSelectionViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return availableThemes.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ThemePreviewCell", for: indexPath) as! ThemePreviewCell
        let theme = availableThemes[indexPath.row]
        let isSelected = theme.name == themeManager.currentTheme.name
        
        cell.configure(with: theme, isSelected: isSelected)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let selectedTheme = availableThemes[indexPath.row]
        themeManager.setTheme(selectedTheme)
        
        // Refresh all cells to update selection state
        tableView.reloadData()
        
        // Update background color
        view.backgroundColor = themeManager.terminalBackgroundColor
        tableView.backgroundColor = themeManager.terminalBackgroundColor
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
}

// MARK: - Theme Preview Cell

class ThemePreviewCell: UITableViewCell {
    
    private let nameLabel = UILabel()
    private let previewView = UIView()
    private let sampleTextLabel = UILabel()
    private let checkmarkImageView = UIImageView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        selectionStyle = .none
        
        nameLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        previewView.layer.cornerRadius = 8
        previewView.layer.borderWidth = 1
        previewView.layer.borderColor = UIColor.separator.cgColor
        previewView.translatesAutoresizingMaskIntoConstraints = false
        
        sampleTextLabel.text = "Sample MUD text"
        sampleTextLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        sampleTextLabel.translatesAutoresizingMaskIntoConstraints = false
        
        checkmarkImageView.image = UIImage(systemName: "checkmark.circle.fill")
        checkmarkImageView.tintColor = .systemBlue
        checkmarkImageView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkImageView.isHidden = true
        
        contentView.addSubview(nameLabel)
        contentView.addSubview(previewView)
        previewView.addSubview(sampleTextLabel)
        contentView.addSubview(checkmarkImageView)
        
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkmarkImageView.leadingAnchor, constant: -8),
            
            previewView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 8),
            previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            previewView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            previewView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            previewView.heightAnchor.constraint(equalToConstant: 32),
            
            sampleTextLabel.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
            sampleTextLabel.leadingAnchor.constraint(equalTo: previewView.leadingAnchor, constant: 8),
            sampleTextLabel.trailingAnchor.constraint(lessThanOrEqualTo: previewView.trailingAnchor, constant: -8),
            
            checkmarkImageView.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            checkmarkImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 24),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    func configure(with theme: MUDTheme, isSelected: Bool) {
        nameLabel.text = theme.name
        previewView.backgroundColor = theme.terminalBackgroundColor
        sampleTextLabel.textColor = theme.terminalTextColor
        checkmarkImageView.isHidden = !isSelected
    }
}

// MARK: - Font Selection View Controller

class FontSelectionViewController: UIViewController {
    
    private var tableView: UITableView!
    private var themeManager: ThemeManager
    private let availableFonts = [
        "SF Mono", "Menlo", "Monaco", "Courier New", "American Typewriter",
        "Andale Mono", "Courier", "Helvetica", "Times New Roman"
    ]
    
    init(themeManager: ThemeManager) {
        self.themeManager = themeManager
        super.init(nibName: nil, bundle: nil)
        title = "Select Font"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = themeManager.terminalBackgroundColor
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
        
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = themeManager.terminalBackgroundColor
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }
}

extension FontSelectionViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return availableFonts.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let fontName = availableFonts[indexPath.row]
        
        cell.textLabel?.text = fontName
        cell.textLabel?.font = UIFont(name: fontName, size: 16) ?? UIFont.systemFont(ofSize: 16)
        
        if fontName == themeManager.currentTheme.fontName {
            cell.accessoryType = .checkmark
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let selectedFont = availableFonts[indexPath.row]
        themeManager.setFontName(selectedFont)
        
        tableView.reloadData()
    }
}

// MARK: - Theme Management View Controller

class ThemeManagementViewController: SettingsViewController {
    
    private var themeManager: ThemeManager
    
    init(themeManager: ThemeManager) {
        self.themeManager = themeManager
        super.init(title: "Manage Themes")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func setupSections() {
        // Implementation would include custom theme management
        let sections: [SettingsSection] = [
            SettingsSection(title: "Custom Themes", items: [
                ActionSettingsItem(title: "Coming Soon", action: {})
            ])
        ]
        setSections(sections)
    }
}

// MARK: - Custom Theme Creator View Controller

class CustomThemeCreatorViewController: SettingsViewController {
    
    private var themeManager: ThemeManager
    private var customTheme: CustomTheme
    private var colorPreviews: [UIView] = []
    
    init(themeManager: ThemeManager) {
        self.themeManager = themeManager
        self.customTheme = CustomTheme()
        super.init(title: "Create Theme")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
    }
    
    private func setupNavigationBar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Save",
            style: .done,
            target: self,
            action: #selector(saveTheme)
        )
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Preview",
            style: .plain,
            target: self,
            action: #selector(previewTheme)
        )
    }
    
    override func setupSections() {
        let sections: [SettingsSection] = [
            createThemeInfoSection(),
            createBackgroundSection(),
            createTextSection(),
            createAnsiSection(),
            createPreviewSection()
        ]
        setSections(sections)
    }
    
    private func createThemeInfoSection() -> SettingsSection {
        return SettingsSection(title: "Theme Information", items: [
            ActionSettingsItem(title: "Theme Name: \(customTheme.name.isEmpty ? "Unnamed" : customTheme.name)") { [weak self] in
                self?.editThemeName()
            }
        ])
    }
    
    private func editThemeName() {
        let alert = UIAlertController(title: "Theme Name", message: "Enter a name for your theme", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.text = self.customTheme.name
            textField.placeholder = "Enter theme name"
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            if let text = alert.textFields?.first?.text {
                self.customTheme.name = text
                self.updateSections()
            }
        })
        
        present(alert, animated: true)
    }
    
    private func createBackgroundSection() -> SettingsSection {
        return SettingsSection(title: "Background Colors", items: [
            ColorPickerSettingsItem(
                title: "Terminal Background",
                color: customTheme.terminalBackground,
                onColorChanged: { [weak self] color in
                    self?.customTheme.terminalBackground = color
                    self?.updatePreview()
                }
            ),
            ColorPickerSettingsItem(
                title: "Interface Background",
                color: customTheme.interfaceBackground,
                onColorChanged: { [weak self] color in
                    self?.customTheme.interfaceBackground = color
                    self?.updatePreview()
                }
            )
        ])
    }
    
    private func createTextSection() -> SettingsSection {
        return SettingsSection(title: "Text Colors", items: [
            ColorPickerSettingsItem(
                title: "Foreground Text",
                color: customTheme.foregroundColor,
                onColorChanged: { [weak self] color in
                    self?.customTheme.foregroundColor = color
                    self?.updatePreview()
                }
            ),
            ColorPickerSettingsItem(
                title: "Link Color",
                color: customTheme.linkColor,
                onColorChanged: { [weak self] color in
                    self?.customTheme.linkColor = color
                    self?.updatePreview()
                }
            ),
            ColorPickerSettingsItem(
                title: "Input Text",
                color: customTheme.inputTextColor,
                onColorChanged: { [weak self] color in
                    self?.customTheme.inputTextColor = color
                    self?.updatePreview()
                }
            )
        ])
    }
    
    private func createAnsiSection() -> SettingsSection {
        return SettingsSection(title: "ANSI Colors", items: [
            ColorPickerSettingsItem(title: "Red", color: customTheme.ansiRed) { [weak self] color in
                self?.customTheme.ansiRed = color
                self?.updatePreview()
            },
            ColorPickerSettingsItem(title: "Green", color: customTheme.ansiGreen) { [weak self] color in
                self?.customTheme.ansiGreen = color
                self?.updatePreview()
            },
            ColorPickerSettingsItem(title: "Yellow", color: customTheme.ansiYellow) { [weak self] color in
                self?.customTheme.ansiYellow = color
                self?.updatePreview()
            },
            ColorPickerSettingsItem(title: "Blue", color: customTheme.ansiBlue) { [weak self] color in
                self?.customTheme.ansiBlue = color
                self?.updatePreview()
            },
            ColorPickerSettingsItem(title: "Magenta", color: customTheme.ansiMagenta) { [weak self] color in
                self?.customTheme.ansiMagenta = color
                self?.updatePreview()
            },
            ColorPickerSettingsItem(title: "Cyan", color: customTheme.ansiCyan) { [weak self] color in
                self?.customTheme.ansiCyan = color
                self?.updatePreview()
            },
            ColorPickerSettingsItem(title: "White", color: customTheme.ansiWhite) { [weak self] color in
                self?.customTheme.ansiWhite = color
                self?.updatePreview()
            }
        ])
    }
    
    private func createPreviewSection() -> SettingsSection {
        return SettingsSection(title: "Theme Presets", items: [
            ActionSettingsItem(title: "Load Dark Preset") { [weak self] in
                self?.loadDarkPreset()
            },
            ActionSettingsItem(title: "Load Light Preset") { [weak self] in
                self?.loadLightPreset()
            },
            ActionSettingsItem(title: "Load Matrix Preset") { [weak self] in
                self?.loadMatrixPreset()
            },
            ActionSettingsItem(title: "Load Amber Preset") { [weak self] in
                self?.loadAmberPreset()
            }
        ])
    }
    
    private func loadDarkPreset() {
        customTheme = CustomTheme(
            name: "Dark Theme",
            terminalBackground: .black,
            interfaceBackground: UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0),
            foregroundColor: .white,
            linkColor: .systemBlue,
            inputTextColor: .white,
            ansiRed: .systemRed,
            ansiGreen: .systemGreen,
            ansiYellow: .systemYellow,
            ansiBlue: .systemBlue,
            ansiMagenta: .systemPurple,
            ansiCyan: .systemTeal,
            ansiWhite: .white
        )
        updateSections()
    }
    
    private func loadLightPreset() {
        customTheme = CustomTheme(
            name: "Light Theme",
            terminalBackground: .white,
            interfaceBackground: UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0),
            foregroundColor: .black,
            linkColor: .systemBlue,
            inputTextColor: .black,
            ansiRed: UIColor(red: 0.8, green: 0, blue: 0, alpha: 1.0),
            ansiGreen: UIColor(red: 0, green: 0.6, blue: 0, alpha: 1.0),
            ansiYellow: UIColor(red: 0.8, green: 0.6, blue: 0, alpha: 1.0),
            ansiBlue: UIColor(red: 0, green: 0, blue: 0.8, alpha: 1.0),
            ansiMagenta: UIColor(red: 0.6, green: 0, blue: 0.6, alpha: 1.0),
            ansiCyan: UIColor(red: 0, green: 0.6, blue: 0.6, alpha: 1.0),
            ansiWhite: .black
        )
        updateSections()
    }
    
    private func loadMatrixPreset() {
        customTheme = CustomTheme(
            name: "Matrix Theme",
            terminalBackground: .black,
            interfaceBackground: UIColor(red: 0.05, green: 0.1, blue: 0.05, alpha: 1.0),
            foregroundColor: UIColor(red: 0, green: 1, blue: 0, alpha: 1.0),
            linkColor: UIColor(red: 0, green: 0.8, blue: 0, alpha: 1.0),
            inputTextColor: UIColor(red: 0, green: 1, blue: 0, alpha: 1.0),
            ansiRed: UIColor(red: 0, green: 0.8, blue: 0, alpha: 1.0),
            ansiGreen: UIColor(red: 0, green: 1, blue: 0, alpha: 1.0),
            ansiYellow: UIColor(red: 0.5, green: 1, blue: 0, alpha: 1.0),
            ansiBlue: UIColor(red: 0, green: 0.6, blue: 0, alpha: 1.0),
            ansiMagenta: UIColor(red: 0, green: 0.8, blue: 0.5, alpha: 1.0),
            ansiCyan: UIColor(red: 0, green: 1, blue: 0.8, alpha: 1.0),
            ansiWhite: UIColor(red: 0, green: 1, blue: 0, alpha: 1.0)
        )
        updateSections()
    }
    
    private func loadAmberPreset() {
        customTheme = CustomTheme(
            name: "Amber Terminal",
            terminalBackground: .black,
            interfaceBackground: UIColor(red: 0.1, green: 0.05, blue: 0, alpha: 1.0),
            foregroundColor: UIColor(red: 1, green: 0.75, blue: 0, alpha: 1.0),
            linkColor: UIColor(red: 1, green: 0.6, blue: 0, alpha: 1.0),
            inputTextColor: UIColor(red: 1, green: 0.75, blue: 0, alpha: 1.0),
            ansiRed: UIColor(red: 1, green: 0.5, blue: 0, alpha: 1.0),
            ansiGreen: UIColor(red: 1, green: 0.7, blue: 0, alpha: 1.0),
            ansiYellow: UIColor(red: 1, green: 0.8, blue: 0, alpha: 1.0),
            ansiBlue: UIColor(red: 0.8, green: 0.6, blue: 0, alpha: 1.0),
            ansiMagenta: UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 1.0),
            ansiCyan: UIColor(red: 1, green: 0.75, blue: 0.5, alpha: 1.0),
            ansiWhite: UIColor(red: 1, green: 0.75, blue: 0, alpha: 1.0)
        )
        updateSections()
    }
    
    private func updateSections() {
        setupSections()
    }
    
    private func updatePreview() {
        // Refresh the table to update color previews
        DispatchQueue.main.async {
            self.setupSections()
        }
    }
    
    @objc private func saveTheme() {
        guard !customTheme.name.isEmpty else {
            showAlert(title: "Invalid Name", message: "Please enter a theme name.")
            return
        }
        
        // Save the custom theme
        let themeData = customTheme.toThemeData()
        UserDefaults.standard.set(themeData, forKey: "CustomTheme_\(customTheme.name)")
        
        // Add to theme manager
        themeManager.addCustomTheme(customTheme)
        
        showAlert(title: "Theme Saved", message: "\(customTheme.name) has been saved successfully!") {
            self.navigationController?.popViewController(animated: true)
        }
    }
    
    @objc private func previewTheme() {
        let previewVC = ThemePreviewViewController(theme: customTheme)
        let navController = UINavigationController(rootViewController: previewVC)
        present(navController, animated: true)
    }
    
    private func showAlert(title: String, message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completion?()
        })
        present(alert, animated: true)
    }
}



// MARK: - Color Picker Settings Item

class ColorPickerSettingsItem: SettingsItem {
    let title: String
    let accessibilityLabel: String?
    let accessibilityHint: String?
    private var currentColor: UIColor
    private let onColorChanged: (UIColor) -> Void
    
    init(title: String, color: UIColor, accessibilityLabel: String? = nil, accessibilityHint: String? = nil, onColorChanged: @escaping (UIColor) -> Void) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.currentColor = color
        self.onColorChanged = onColorChanged
    }
    
    func configureCell(_ cell: UITableViewCell, in tableView: UITableView, at indexPath: IndexPath) {
        cell.textLabel?.text = title
        cell.accessoryType = .disclosureIndicator
        
        // Create color preview
        let colorPreview = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        colorPreview.backgroundColor = currentColor
        colorPreview.layer.borderWidth = 1
        colorPreview.layer.borderColor = UIColor.gray.cgColor
        colorPreview.layer.cornerRadius = 4
        
        cell.accessoryView = colorPreview
    }
    
    func didSelectCell(in viewController: UIViewController, at indexPath: IndexPath) {
        if #available(iOS 14.0, *) {
            let colorPicker = UIColorPickerViewController()
            colorPicker.selectedColor = currentColor
            let delegate = ColorPickerDelegate(item: self)
            colorPicker.delegate = delegate
            // Store delegate to prevent deallocation
            objc_setAssociatedObject(colorPicker, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            viewController.present(colorPicker, animated: true)
        } else {
            // Fallback for iOS 13
            showColorSelectionAlert(in: viewController)
        }
    }
    
    private func showColorSelectionAlert(in viewController: UIViewController) {
        let alert = UIAlertController(title: "Select Color", message: "Choose a predefined color", preferredStyle: .actionSheet)
        
        let colors: [(String, UIColor)] = [
            ("Black", .black),
            ("White", .white),
            ("Red", .systemRed),
            ("Green", .systemGreen),
            ("Blue", .systemBlue),
            ("Yellow", .systemYellow),
            ("Orange", .systemOrange),
            ("Purple", .systemPurple),
            ("Pink", .systemPink),
            ("Teal", .systemTeal),
            ("Gray", .systemGray)
        ]
        
        for (name, color) in colors {
            alert.addAction(UIAlertAction(title: name, style: .default) { _ in
                self.updateColor(color)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        viewController.present(alert, animated: true)
    }
    
    func updateColor(_ color: UIColor) {
        currentColor = color
        onColorChanged(color)
    }
}

// MARK: - Color Picker Delegate

@available(iOS 14.0, *)
class ColorPickerDelegate: NSObject, UIColorPickerViewControllerDelegate {
    private let item: ColorPickerSettingsItem
    
    init(item: ColorPickerSettingsItem) {
        self.item = item
    }
    
    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        item.updateColor(viewController.selectedColor)
    }
}



// MARK: - Theme Preview Controller

class ThemePreviewViewController: UIViewController {
    
    private let theme: CustomTheme
    private var textView: UITextView!
    
    init(theme: CustomTheme) {
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
        title = "\(theme.name) Preview"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadPreviewContent()
    }
    
    private func setupUI() {
        view.backgroundColor = theme.interfaceBackground
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
        
        textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = theme.terminalBackground
        textView.textColor = theme.foregroundColor
        textView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isEditable = false
        textView.contentInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        
        view.addSubview(textView)
        
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }
    
    private func loadPreviewContent() {
        let content = NSMutableAttributedString()
        
        // Add sample text with different colors
        content.append(createColoredText("Welcome to \(theme.name)\n\n", color: theme.foregroundColor))
        content.append(createColoredText("This is normal text.\n", color: theme.foregroundColor))
        content.append(createColoredText("This is a link.\n", color: theme.linkColor))
        content.append(createColoredText("\nANSI Color Preview:\n", color: theme.foregroundColor))
        content.append(createColoredText("Red text sample\n", color: theme.ansiRed))
        content.append(createColoredText("Green text sample\n", color: theme.ansiGreen))
        content.append(createColoredText("Yellow text sample\n", color: theme.ansiYellow))
        content.append(createColoredText("Blue text sample\n", color: theme.ansiBlue))
        content.append(createColoredText("Magenta text sample\n", color: theme.ansiMagenta))
        content.append(createColoredText("Cyan text sample\n", color: theme.ansiCyan))
        content.append(createColoredText("White text sample\n", color: theme.ansiWhite))
        
        textView.attributedText = content
    }
    
    private func createColoredText(_ text: String, color: UIColor) -> NSAttributedString {
        return NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        ])
    }
    
    @objc private func doneTapped() {
        dismiss(animated: true)
    }
} 