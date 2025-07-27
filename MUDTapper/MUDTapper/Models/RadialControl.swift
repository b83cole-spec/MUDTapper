import UIKit
import Foundation

// MARK: - RadialDirection

enum RadialDirection: String, CaseIterable {
    case north = "N"
    case northeast = "NE"
    case east = "E"
    case southeast = "SE"
    case south = "S"
    case southwest = "SW"
    case west = "W"
    case northwest = "NW"
    
    var defaultCommand: String {
        switch self {
        case .north: return "north"
        case .northeast: return "northeast"
        case .east: return "east"
        case .southeast: return "southeast"
        case .south: return "south"
        case .southwest: return "southwest"
        case .west: return "west"
        case .northwest: return "northwest"
        }
    }
    
    var angle: Double {
        switch self {
        case .north: return 0
        case .northeast: return 45
        case .east: return 90
        case .southeast: return 135
        case .south: return 180
        case .southwest: return 225
        case .west: return 270
        case .northwest: return 315
        }
    }
}

// MARK: - RadialControlStyle

enum RadialControlStyle: String, CaseIterable {
    case standard = "standard"
    case minimal = "minimal"
    case transparent = "transparent"
    case outline = "outline"
    case hidden = "hidden"
    
    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .minimal: return "Minimal"
        case .transparent: return "Transparent"
        case .outline: return "Outline Only"
        case .hidden: return "Hidden"
        }
    }
    
    var description: String {
        switch self {
        case .standard: return "Full circle with labels and background"
        case .minimal: return "Small circle with minimal visual elements"
        case .transparent: return "Very transparent with subtle indicators"
        case .outline: return "Just outline border, no background"
        case .hidden: return "Completely hidden until activated"
        }
    }
}

// MARK: - RadialControl

class RadialControl {
    
    // MARK: - Validation
    
    static func validateRadialPositions() {
        let moveControlPosition = UserDefaults.standard.integer(forKey: UserDefaultsKeys.moveControl)
        let radialControlPosition = UserDefaults.standard.integer(forKey: UserDefaultsKeys.radialControl)
        
        // Ensure positions are valid
        if !RadialControlPosition.allCases.map({ $0.rawValue }).contains(moveControlPosition) {
            UserDefaults.standard.set(RadialControlPosition.right.rawValue, forKey: UserDefaultsKeys.moveControl)
        }
        
        if !RadialControlPosition.allCases.map({ $0.rawValue }).contains(radialControlPosition) {
            UserDefaults.standard.set(RadialControlPosition.left.rawValue, forKey: UserDefaultsKeys.radialControl)
        }
        
        // Ensure they're not in the same position (unless both are hidden)
        if moveControlPosition == radialControlPosition && 
           moveControlPosition != RadialControlPosition.hidden.rawValue {
            UserDefaults.standard.set(RadialControlPosition.right.rawValue, forKey: UserDefaultsKeys.moveControl)
            UserDefaults.standard.set(RadialControlPosition.left.rawValue, forKey: UserDefaultsKeys.radialControl)
        }
    }
    
    // MARK: - Default Commands
    
    static func defaultRadialCommands() -> [String] {
        return UserDefaults.standard.array(forKey: UserDefaultsKeys.radialCommands) as? [String] ?? 
               ["up", "in", "down", "out", "look"]
    }
    
    static func setRadialCommands(_ commands: [String]) {
        UserDefaults.standard.set(commands, forKey: UserDefaultsKeys.radialCommands)
    }
    
    // MARK: - Position Management
    
    static func moveControlPosition() -> RadialControlPosition {
        let rawValue = UserDefaults.standard.integer(forKey: UserDefaultsKeys.moveControl)
        return RadialControlPosition(rawValue: rawValue) ?? .right
    }
    
    static func radialControlPosition() -> RadialControlPosition {
        let rawValue = UserDefaults.standard.integer(forKey: UserDefaultsKeys.radialControl)
        return RadialControlPosition(rawValue: rawValue) ?? .left
    }
    
    static func setMoveControlPosition(_ position: RadialControlPosition) {
        UserDefaults.standard.set(position.rawValue, forKey: UserDefaultsKeys.moveControl)
        validateRadialPositions()
    }
    
    static func setRadialControlPosition(_ position: RadialControlPosition) {
        UserDefaults.standard.set(position.rawValue, forKey: UserDefaultsKeys.radialControl)
        validateRadialPositions()
    }
    
    // MARK: - Style Management
    
    static func radialControlStyle() -> RadialControlStyle {
        let rawValue = UserDefaults.standard.string(forKey: UserDefaultsKeys.radialControlStyle) ?? RadialControlStyle.standard.rawValue
        return RadialControlStyle(rawValue: rawValue) ?? .standard
    }
    
    static func setRadialControlStyle(_ style: RadialControlStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: UserDefaultsKeys.radialControlStyle)
    }
    
    static func radialControlOpacity() -> Double {
        return UserDefaults.standard.double(forKey: UserDefaultsKeys.radialControlOpacity)
    }
    
    static func setRadialControlOpacity(_ opacity: Double) {
        UserDefaults.standard.set(opacity, forKey: UserDefaultsKeys.radialControlOpacity)
    }
    
    static func radialControlSize() -> Double {
        return UserDefaults.standard.double(forKey: UserDefaultsKeys.radialControlSize)
    }
    
    static func setRadialControlSize(_ size: Double) {
        UserDefaults.standard.set(size, forKey: UserDefaultsKeys.radialControlSize)
    }
    
    static func radialControlLabelsVisible() -> Bool {
        return UserDefaults.standard.bool(forKey: UserDefaultsKeys.radialControlLabelsVisible)
    }
    
    static func setRadialControlLabelsVisible(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: UserDefaultsKeys.radialControlLabelsVisible)
    }
} 