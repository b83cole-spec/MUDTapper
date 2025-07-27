import Foundation
import CoreData

// MARK: - Notification Names

extension Notification.Name {
    static let triggerDidFire = Notification.Name("triggerDidFire")
    static let triggerSoundRequested = Notification.Name("triggerSoundRequested")
    static let triggerVibrationRequested = Notification.Name("triggerVibrationRequested")
}

@objc(World)
public class World: NSManagedObject, LoggableWorld {
    
    // MARK: - Core Data Properties
    
    @NSManaged public var hostname: String?
    @NSManaged public var name: String?
    @NSManaged public var port: Int32
    @NSManaged public var isDefault: Bool
    @NSManaged public var isFavorite: Bool
    @NSManaged public var isHidden: Bool
    @NSManaged public var isSecure: Bool
    @NSManaged public var connectCommand: String?
    @NSManaged public var lastConnected: Date?
    @NSManaged public var lastModified: Date?
    @NSManaged public var username: String?
    @NSManaged public var password: String?
    @NSManaged public var autoConnect: Bool
    @NSManaged public var sortOrder: Int32
    
    // MARK: - Relationships
    
    @NSManaged public var aliases: Set<Alias>?
    @NSManaged public var triggers: Set<Trigger>?
    @NSManaged public var gags: Set<Gag>?
    @NSManaged public var tickers: Set<Ticker>?
    
    // MARK: - Computed Properties
    
    var worldDescription: String {
        if let name = name, !name.isEmpty {
            return name + " "
        }
        
        var description = ""
        if let hostname = hostname {
            description += hostname
        }
        description += ":\(port)"
        
        return description
    }
    
    var canSave: Bool {
        guard let hostname = hostname, !hostname.isEmpty else { return false }
        return port > 0 && port <= UInt16.max
    }
    
    // MARK: - Creation Methods
    
    static func createWorld(in context: NSManagedObjectContext) -> World {
        let world = World(context: context)
        world.port = 23
        world.isDefault = false
        world.isSecure = false
        world.isHidden = false
        world.lastModified = Date()
        return world
    }
    
    static func createWorld(from dictionary: [String: Any], in context: NSManagedObjectContext) -> World {
        let world = createWorld(in: context)
        
        if let name = dictionary["name"] as? String {
            world.name = name
        }
        if let hostname = dictionary["hostname"] as? String {
            world.hostname = hostname
        }
        if let port = dictionary["port"] as? Int32 {
            world.port = port
        }
        if let isSecure = dictionary["isSecure"] as? Bool {
            world.isSecure = isSecure
        }
        if let connectCommand = dictionary["connectCommand"] as? String {
            world.connectCommand = connectCommand
        }
        
        return world
    }
    
    static func createWorld(from url: URL, in context: NSManagedObjectContext) -> World {
        let world = createWorld(in: context)
        world.hostname = url.host
        
        if let port = url.port {
            world.port = Int32(port)
        }
        
        return world
    }
    
    // MARK: - Default World Management
    
    func setAsDefaultWorld() {
        guard !isDefault else { return }
        
        let context = managedObjectContext!
        
        // Set all other worlds to not default
        let request: NSFetchRequest<World> = World.fetchRequest()
        request.predicate = NSPredicate(format: "isDefault == YES")
        
        do {
            let defaultWorlds = try context.fetch(request)
            for world in defaultWorlds {
                world.isDefault = false
                world.lastModified = Date()
            }
            
            // Set this world as default
            isDefault = true
            lastModified = Date()
            
            try context.save()
        } catch {
            print("Error setting default world: \(error)")
        }
    }
    
    static func defaultWorld(in context: NSManagedObjectContext) -> World? {
        let request: NSFetchRequest<World> = World.fetchRequest()
        request.predicate = NSPredicate(format: "isHidden == NO AND isDefault == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \World.name, ascending: true)]
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            print("Error fetching default world: \(error)")
            return nil
        }
    }
    
    // MARK: - Default Worlds Creation
    
    static func createDefaultWorldsIfNecessary() {
        let hasCreatedWorlds = UserDefaults.standard.bool(forKey: UserDefaultsKeys.initialWorldsCreated)
        
        if !hasCreatedWorlds {
            createDefaultWorlds()
        }
    }
    
    private static func createDefaultWorlds() {
        let context = PersistenceController.shared.newBackgroundContext()
        
        context.perform {
            guard let worldsPath = Bundle.main.path(forResource: "DefaultWorlds", ofType: "plist"),
                  let worldsList = NSArray(contentsOfFile: worldsPath) as? [[String: Any]] else {
                print("Could not load default worlds")
                return
            }
            
            for worldDict in worldsList {
                _ = World.createWorld(from: worldDict, in: context)
            }
            
            do {
                try context.save()
                
                DispatchQueue.main.async {
                    UserDefaults.standard.set(true, forKey: UserDefaultsKeys.initialWorldsCreated)
                }
            } catch {
                print("Error saving default worlds: \(error)")
            }
        }
    }
    
    // MARK: - Hostname Cleaning
    
    static func cleanedHostname(from host: String?) -> String {
        guard let host = host, !host.isEmpty else { return "" }
        
        let allowedCharacters = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: ".-"))
        
        var cleanedHost = host.lowercased()
        
        // Remove protocol if present
        if let range = cleanedHost.range(of: "://") {
            cleanedHost = String(cleanedHost[range.upperBound...])
        }
        
        return cleanedHost.components(separatedBy: allowedCharacters.inverted).joined()
    }
    
    // MARK: - Deep Clone
    
    func deepClone(completion: @escaping () -> Void) {
        let worldID = objectID
        let context = PersistenceController.shared.newBackgroundContext()
        
        context.perform {
            guard let sourceWorld = try? context.existingObject(with: worldID) as? World else {
                DispatchQueue.main.async { completion() }
                return
            }
            
            let newWorld = World.createWorld(in: context)
            newWorld.name = sourceWorld.name
            newWorld.hostname = sourceWorld.hostname
            newWorld.port = sourceWorld.port
            newWorld.isSecure = sourceWorld.isSecure
            newWorld.connectCommand = sourceWorld.connectCommand
            
            // Clone triggers
            if let triggers = sourceWorld.triggers {
                for trigger in triggers {
                    let newTrigger = Trigger(context: context)
                    newTrigger.trigger = trigger.trigger
                    newTrigger.isEnabled = trigger.isEnabled
                    newTrigger.commands = trigger.commands
                    newTrigger.soundFileName = trigger.soundFileName
                    newTrigger.highlightColor = trigger.highlightColor
                    newTrigger.vibrate = trigger.vibrate
                    newTrigger.triggerType = trigger.triggerType
                    newTrigger.world = newWorld
                }
            }
            
            // Clone aliases
            if let aliases = sourceWorld.aliases {
                for alias in aliases {
                    let newAlias = Alias(context: context)
                    newAlias.name = alias.name
                    newAlias.commands = alias.commands
                    newAlias.isEnabled = alias.isEnabled
                    newAlias.world = newWorld
                }
            }
            
            // Clone gags
            if let gags = sourceWorld.gags {
                for gag in gags {
                    let newGag = Gag(context: context)
                    newGag.gag = gag.gag
                    newGag.isEnabled = gag.isEnabled
                    newGag.gagType = gag.gagType
                    newGag.world = newWorld
                }
            }
            
            // Clone tickers
            if let tickers = sourceWorld.tickers {
                for ticker in tickers {
                    let newTicker = Ticker(context: context)
                    newTicker.interval = ticker.interval
                    newTicker.isEnabled = ticker.isEnabled
                    newTicker.commands = ticker.commands
                    newTicker.soundFileName = ticker.soundFileName
                    newTicker.world = newWorld
                }
            }
            
            do {
                try context.save()
                DispatchQueue.main.async { completion() }
            } catch {
                print("Error cloning world: \(error)")
                DispatchQueue.main.async { completion() }
            }
        }
    }
    
    // MARK: - Ordered Collections
    
    func orderedTriggers(active: Bool) -> [Trigger] {
        guard let triggers = triggers else { return [] }
        
        return triggers
            .filter { $0.isEnabled == active }
            .sorted { ($0.trigger ?? "") < ($1.trigger ?? "") }
    }
    
    func orderedAliases() -> [Alias] {
        guard let aliases = aliases else { return [] }
        
        return aliases.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
    
    func orderedGags() -> [Gag] {
        guard let gags = gags else { return [] }
        
        return gags.sorted { ($0.gag ?? "") < ($1.gag ?? "") }
    }
    
    func orderedTickers() -> [Ticker] {
        guard let tickers = tickers else { return [] }
        
        return tickers.sorted { $0.interval < $1.interval }
    }
    
    // MARK: - Alias Processing
    
    func commandsForMatchingAlias(input: String) -> [String]? {
        guard !input.isEmpty else { return nil }
        
        let words = input.components(separatedBy: .whitespaces)
        guard let command = words.first else { return nil }
        
        let matchingAliases = orderedAliases().filter { alias in
            guard let aliasName = alias.name, !aliasName.isEmpty else { return false }
            return aliasName.lowercased() == command.lowercased()
        }
        
        if let alias = matchingAliases.first {
            return alias.aliasCommands(for: input)
        }
        
        return nil
    }
    
    // MARK: - Gag Processing
    
    func filteredIndexes(byMatchingGagsIn lines: [String]) -> IndexSet {
        var indexes = IndexSet(integersIn: 0..<lines.count)
        
        guard !orderedGags().isEmpty else { return indexes }
        
        for (index, line) in lines.enumerated() {
            for gag in orderedGags() {
                if gag.matches(line: line) {
                    indexes.remove(index)
                    break
                }
            }
        }
        
        return indexes
    }
    
    // MARK: - MushClient-Style Trigger Processing
    
    func processTriggersForText(_ text: String, loggingCallback: ((String, Bool) -> Void)? = nil) {
        guard let context = managedObjectContext else { return }
        
        // Performance optimization: skip processing if no text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Get active triggers ordered by priority (MushClient style)
        let activeTriggers = Trigger.fetchActiveTriggersOrderedByPriority(for: self, context: context)
        
        // Performance optimization: skip processing if no active triggers
        guard !activeTriggers.isEmpty else {
            // Still handle logging if callback provided
            if let callback = loggingCallback {
                let lines = text.components(separatedBy: .newlines)
                for line in lines {
                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedLine.isEmpty {
                        callback(trimmedLine, true)
                    }
                }
            }
            return
        }
        
        // Split text into lines for processing
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }
            
            processMushClientTriggersForLine(trimmedLine, triggers: activeTriggers, loggingCallback: loggingCallback)
        }
    }
    
    private func processMushClientTriggersForLine(_ line: String, triggers: [Trigger], loggingCallback: ((String, Bool) -> Void)? = nil) {
        var shouldOmitLine = false
        var shouldOmitFromLog = false
        
        // Debug: Log the line being processed
        print("🔍 Processing line: '\(line)'")
        
        for trigger in triggers {
            // Debug: Log each trigger being checked
            print("  📋 Checking trigger: '\(trigger.trigger ?? "")' (type: \(trigger.triggerTypeEnum.displayName))")
            
            // Check if trigger matches first
            if trigger.matches(line: line) {
                print("  ✅ TRIGGER MATCHED!")
                print("  📋 Trigger commands: '\(trigger.commands ?? "")'")
                
                // Execute the trigger and get whether to continue
                let shouldContinue = trigger.execute(for: line)
                print("  🔄 Should continue evaluating: \(shouldContinue)")
                
                // Check if this trigger should omit the line from output
                if trigger.shouldOmitFromOutput {
                    shouldOmitLine = true
                }
                
                // Check if this trigger should omit the line from logging
                if trigger.shouldOmitFromLog {
                    shouldOmitFromLog = true
                }
                
                // Handle sound and vibration (legacy support)
                if let soundFileName = trigger.soundFileName, !soundFileName.isEmpty {
                    NotificationCenter.default.post(
                        name: .triggerSoundRequested,
                        object: self,
                        userInfo: ["soundFileName": soundFileName]
                    )
                }
                
                if trigger.vibrate {
                    NotificationCenter.default.post(
                        name: .triggerVibrationRequested,
                        object: self
                    )
                }
                
                // If this trigger doesn't want to keep evaluating, stop here
                if !shouldContinue {
                    break
                }
            }
        }
        
        // Handle logging
        loggingCallback?(line, !shouldOmitFromLog)
        
        // Handle line omission
        if shouldOmitLine {
            NotificationCenter.default.post(
                name: NSNotification.Name("OmitLineFromOutput"),
                object: self,
                userInfo: ["line": line]
            )
        }
    }
    
    // MARK: - Gag Processing
    
    func shouldGagText(_ text: String) -> Bool {
        guard let gags = gags else { return false }
        
        for gag in Array(gags) where gag.isEnabled {
            if let gagText = gag.gag, !gagText.isEmpty {
                if text.contains(gagText) {
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Variable Management
    
    func setVariable(_ key: String, value: String) {
        // Variables are not managed in the Core Data model
    }
    
    func getVariable(_ key: String) -> String? {
        // Variables are not managed in the Core Data model
        return nil
    }
    
    func removeVariable(_ key: String) {
        // Variables are not managed in the Core Data model
    }
    
    func getAllVariables() -> [String: String] {
        // Variables are not managed in the Core Data model
        return [:]
    }
}

// MARK: - Core Data Fetch Request

extension World {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<World> {
        return NSFetchRequest<World>(entityName: "World")
    }
    
    static func predicateForRecords(with world: World) -> NSPredicate {
        return NSPredicate(format: "world == %@ AND isHidden == NO", world)
    }
} 