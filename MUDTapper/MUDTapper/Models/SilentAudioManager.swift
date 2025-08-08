import AVFoundation
import Foundation
import UIKit

class SilentAudioManager {
    static let shared = SilentAudioManager()
    
    private var audioPlayer: AVAudioPlayer?
    private var audioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    private var isPlaying = false
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    private var audioSessionActive = false
    
    private init() {
        setupAudioSession()
        setupNotifications()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            print("SilentAudioManager: Audio session interrupted")
            // Don't stop our background audio - it's important for connection maintenance
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    print("SilentAudioManager: Resuming audio after interruption")
                    restartBackgroundAudio()
                }
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioSessionRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        print("SilentAudioManager: Audio route changed: \(reason)")
        
        // Restart background audio to adapt to new route
        if isPlaying {
            restartBackgroundAudio()
        }
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try audioSession.setActive(true)
            audioSessionActive = true
        #if DEBUG
        print("SilentAudioManager: Audio session configured successfully")
        #endif
        } catch {
            #if DEBUG
            print("SilentAudioManager: Failed to setup audio session: \(error)")
            #endif
            audioSessionActive = false
        }
    }
    
    func startBackgroundAudio() {
        // Check if background audio is disabled by user preference
        guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.backgroundAudioEnabled) else {
            #if DEBUG
            print("SilentAudioManager: Background audio disabled by user preference")
            #endif
            return
        }
        
        guard !isPlaying else { 
            #if DEBUG
            print("SilentAudioManager: Background audio already playing")
            #endif
            return 
        }
        
        #if DEBUG
        print("SilentAudioManager: Starting background audio")
        #endif
        
        // Ensure audio session is active
        if !audioSessionActive {
            setupAudioSession()
        }
        
        // Start background task to protect audio setup
        startBackgroundTask()
        
        // Try multiple audio strategies for maximum background protection
        let audioStarted = startAudioEngine() || startAudioPlayer()
        
        if audioStarted {
            isPlaying = true
            #if DEBUG
            print("SilentAudioManager: Background audio started successfully")
            #endif
        } else {
            #if DEBUG
            print("SilentAudioManager: Failed to start background audio")
            #endif
            endBackgroundTask()
        }
    }
    
    private func startAudioEngine() -> Bool {
        // Create a silent audio buffer
        let sampleRate: Double = 44100
        let duration: Double = 1.0 // 1 second loop
        let frameCount = Int(sampleRate * duration)
        
        guard let audioFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            #if DEBUG
            print("SilentAudioManager: Failed to create audio format")
            #endif
            return false
        }
        
        guard let audioBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            #if DEBUG
            print("SilentAudioManager: Failed to create audio buffer")
            #endif
            return false
        }
        
        audioBuffer.frameLength = AVAudioFrameCount(frameCount)
        
        // Fill with completely silent audio
        if let channelData = audioBuffer.floatChannelData {
            for frame in 0..<frameCount {
                channelData[0][frame] = 0.0 // Completely silent
            }
        }
        
        // Setup audio engine
        audioEngine = AVAudioEngine()
        audioPlayerNode = AVAudioPlayerNode()
        
        guard let engine = audioEngine, let playerNode = audioPlayerNode else {
            print("SilentAudioManager: Failed to create audio engine components")
            return false
        }
        
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: audioBuffer.format)
        
        do {
            try engine.start()
            
            // Schedule the buffer to loop indefinitely
            playerNode.scheduleBuffer(audioBuffer, at: nil, options: .loops, completionHandler: nil)
            playerNode.play()
            
            #if DEBUG
            print("SilentAudioManager: Audio engine started successfully")
            #endif
            return true
        } catch {
            #if DEBUG
            print("SilentAudioManager: Failed to start audio engine: \(error)")
            #endif
            return false
        }
    }
    
    private func startAudioPlayer() -> Bool {
        // Create silent audio data as fallback
        let sampleRate = 44100.0
        let duration = 1.0
        let frameCount = Int(sampleRate * duration)
        
        // Create WAV data for very quiet audio
        var audioData = Data()
        
        // WAV header (44 bytes)
        let wavHeader: [UInt8] = [
            0x52, 0x49, 0x46, 0x46, // "RIFF"
            0x00, 0x00, 0x00, 0x00, // File size (will be set later)
            0x57, 0x41, 0x56, 0x45, // "WAVE"
            0x66, 0x6D, 0x74, 0x20, // "fmt "
            0x10, 0x00, 0x00, 0x00, // Subchunk size (16)
            0x01, 0x00, 0x01, 0x00, // Audio format (1), channels (1)
            0x44, 0xAC, 0x00, 0x00, // Sample rate (44100)
            0x88, 0x58, 0x01, 0x00, // Byte rate
            0x02, 0x00, 0x10, 0x00, // Block align (2), bits per sample (16)
            0x64, 0x61, 0x74, 0x61, // "data"
            0x00, 0x00, 0x00, 0x00  // Data size (will be set later)
        ]
        
        audioData.append(contentsOf: wavHeader)
        
        // Add silent audio samples
        for _ in 0..<frameCount {
            let sample: Int16 = 0 // Completely silent
            let sampleBytes = withUnsafeBytes(of: sample.littleEndian) { Array($0) }
            audioData.append(contentsOf: sampleBytes)
        }
        
        // Update file size in header
        let fileSize = UInt32(audioData.count - 8)
        audioData.replaceSubrange(4..<8, with: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        
        // Update data size in header
        let dataSize = UInt32(frameCount * 2)
        audioData.replaceSubrange(40..<44, with: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        
        do {
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.numberOfLoops = -1 // Loop indefinitely
            audioPlayer?.volume = 0.0 // Completely silent
            audioPlayer?.rate = 1.0 // Normal playback rate
            
            // Double check the volume is actually 0
            #if DEBUG
            print("SilentAudioManager: Audio player volume set to: \(audioPlayer?.volume ?? -1)")
            #endif
            
            if audioPlayer?.play() == true {
                #if DEBUG
                print("SilentAudioManager: Audio player started successfully")
                #endif
                return true
            } else {
                #if DEBUG
                print("SilentAudioManager: Failed to start audio player")
                #endif
                return false
            }
        } catch {
            #if DEBUG
            print("SilentAudioManager: Failed to create audio player: \(error)")
            #endif
            return false
        }
    }
    
    private func restartBackgroundAudio() {
        #if DEBUG
        print("SilentAudioManager: Restarting background audio")
        #endif
        stopBackgroundAudio()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.startBackgroundAudio()
        }
    }
    
    private func startBackgroundTask() {
        endBackgroundTask()
        
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "SilentAudio-Maintenance") {
            #if DEBUG
            print("SilentAudioManager: Background task expired")
            #endif
            self.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
    }
    
    func stopBackgroundAudio() {
        guard isPlaying else { return }
        
        #if DEBUG
        print("SilentAudioManager: Stopping background audio")
        #endif
        
        audioPlayerNode?.stop()
        audioEngine?.stop()
        audioPlayer?.stop()
        
        audioPlayerNode = nil
        audioEngine = nil
        audioPlayer = nil
        isPlaying = false
        
        endBackgroundTask()
        
        #if DEBUG
        print("SilentAudioManager: Background audio stopped")
        #endif
    }
    
    func isBackgroundAudioPlaying() -> Bool {
        return isPlaying
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopBackgroundAudio()
    }
} 