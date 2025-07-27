# MUDTapper

A modern iOS MUD (Multi-User Dungeon text game) client built in Swift.

## Overview

MUDTapper is a modern MUD client built for current iOS versions, providing powerful automation features and an intuitive user experience.

## Features

### Core Functionality
- **Multiple World Support**: Connect to multiple MUD servers with individual configurations
- **Telnet Protocol**: Full telnet client implementation with ANSI color support
- **Alias System**: Create command shortcuts with parameter substitution ($1$, $2$, $*$)
- **Trigger System**: Automated responses to incoming text with highlighting and sound
- **Gag System**: Filter unwanted text from display
- **Ticker System**: Execute commands at timed intervals
- **Theme Support**: Multiple terminal themes (Classic Dark/Light, Amber Terminal, Matrix)

### Modern iOS Features
- **iOS 15.0+ Support**: Modern deployment target with latest iOS features
- **Scene Delegate**: Full support for iOS 13+ scene-based architecture
- **Core Data**: Modern Core Data stack with automatic migration
- **Swift Package Manager**: Updated dependencies using SPM
- **Dark Mode**: Automatic theme adaptation
- **URL Schemes**: Support for telnet:// URLs

### UI/UX Features
- **Side Menu Navigation**: Swipe-based world selection
- **Radial Controls**: Touch-friendly movement controls
- **Custom Fonts**: Support for multiple monospace terminal fonts
- **ANSI Color Processing**: Full terminal color and formatting support
- **Local Echo**: Optional command echoing
- **Manual World Selection**: Choose your world before connecting

## Technical Details

### Architecture
- **Swift 5.9**: Modern Swift with latest language features
- **iOS 15.0+**: Minimum deployment target
- **Core Data**: Data persistence with automatic migration
- **CocoaAsyncSocket**: Reliable networking for telnet connections
- **ANSI Processing**: Custom engine for terminal escape sequences

### Dependencies
- CocoaAsyncSocket (7.6.5+): Networking
- Masonry (1.1.0+): Auto Layout
- TTTAttributedLabel (2.0.0+): Rich text display
- JSQSystemSoundPlayer (2.0.1+): Sound effects
- VTAcknowledgementsViewController (1.5.5+): Open source acknowledgments

### Project Structure
```
MUDTapper/
├── MUDTapper/
│   ├── AppDelegate.swift           # App lifecycle
│   ├── SceneDelegate.swift         # Scene management
│   ├── Models/                     # Core Data models
│   │   ├── PersistenceController.swift
│   │   ├── World.swift
│   │   ├── Alias.swift
│   │   ├── Trigger.swift
│   │   ├── Gag.swift
│   │   ├── Ticker.swift
│   │   ├── ThemeManager.swift
│   │   ├── NotificationManager.swift
│   │   └── RadialControl.swift
│   ├── Controllers/                # View controllers
│   │   ├── ClientContainer.swift
│   │   └── ClientViewController.swift
│   ├── Network/                    # Networking layer
│   │   ├── MUDSocket.swift
│   │   └── ANSIProcessor.swift
│   ├── Resources/                  # App resources
│   │   ├── DefaultWorlds.plist
│   │   └── LaunchScreen.storyboard
│   └── MUDTapper.xcdatamodeld/     # Core Data model
└── project.yml                     # XcodeGen configuration
```

## Setup Instructions

### Prerequisites
- Xcode 15.0+
- iOS 15.0+ device or simulator
- XcodeGen (for project generation)

### Installation
1. Clone the repository
2. Install XcodeGen: `brew install xcodegen`
3. Generate the Xcode project: `xcodegen generate`
4. Open `MUDTapper.xcodeproj` in Xcode
5. Build and run

### Built-in MUD Worlds
The app includes several default MUD worlds for testing:
- 3Kingdoms (3k.org:3000)
- Aardwolf (aardmud.org:23)
- Discworld MUD (discworld.starturtle.net:23)
- BatMUD (batmud.bat.org:23)

## Usage

1. Launch MUDTapper
2. Select a world from the world list (tap the worlds button)
3. Connect and start playing!
4. Use the side menu to access automation features
5. Customize themes and settings to your preference

## Support

- iOS 15.0 and later
- iPhone and iPad compatible
- Supports both portrait and landscape orientations

## Contributing

This project focuses on providing a modern, reliable MUD client for iOS. Contributions that improve functionality, performance, or user experience are welcome.

## License

This project is open source. See the LICENSE file for details.

## Acknowledgments

Inspired by the original MUDRammer by Splinesoft. This project has evolved significantly with many new features and improvements while maintaining the core MUD client functionality. 
