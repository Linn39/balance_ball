//
//  ContentView.swift
//  LaserCat
//
//  Created by Lin Zhou on 08.02.26.
//

import SwiftUI
import CoreMotion
import AVFoundation
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    enum MovementMode {
        case easy   // old: move towards target position
        case difficult // new: velocity-based
    }

    // 1. Sensor & Position State
    @State private var catPosition = CGPoint(x: 200, y: 400)
    @State private var motion = CMMotionManager()
    @State private var laserPosition = CGPoint(x: 150, y: 300)
    @State private var laserColor: Color = .red
    @State private var isLaserHit: Bool = false
    @State private var hitCount: Int = 0
    @State private var lastHitDate: Date? = nil
    @State private var totalHitInterval: TimeInterval = 0
    @State private var movementMode: MovementMode? = nil
    @State private var screenSize: CGSize = .zero
    @State private var catchSoundPlayer: AVAudioPlayer?
    @State private var soundEnabled: Bool = true
    @State private var lastSignificantMovementDate: Date? = nil
    @State private var gameEndDeadline: Date?
    @State private var gameOver = false
    #if os(iOS)
    @State private var idleTimer: Timer?
    @AppStorage(OrientationPreference.useLandscapeKey) private var preferredOrientationIsLandscape = false
    #endif
    
    // 2. Sensitivity Settings (Adjust these for your balance board!)
    let sensitivity: CGFloat = 50.0
    let damping: CGFloat = 0.15 // Lower = smoother/slower, Higher = twitchier
    let laserRadius: CGFloat = 25.0
    let catSize: CGFloat = 60.0
    /// Initial countdown and bar scale; extra time from hits shows as a full bar until remaining drops below this.
    let roundTimeSeconds: TimeInterval = 60
    let bonusSecondsPerHit: TimeInterval = 1

    /// Idle timer: gyro magnitude (rad/s) above this = "significant movement". Still device ≈ 0; moving the board gives 0.1–1+.
    let movementThresholdGyro: Double = 0.05

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                if movementMode == nil {
                    // Start page
                    VStack(spacing: 24) {
                        // Top bar: rotation lock and sound
                        HStack {
                            Spacer()
                            #if os(iOS)
                            Button {
                                preferredOrientationIsLandscape.toggle()
                                OrientationPreference.setLandscape(preferredOrientationIsLandscape)
                                applyPreferredOrientation()
                            } label: {
                                Image(systemName: "rotate.right")
                                    .font(.title)
                                    .foregroundColor(.white)
                            }
                            Spacer()
                            #endif
                            Button {
                                soundEnabled.toggle()
                                configureAudioSession()
                            } label: {
                                Image(systemName: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                            }
                            Spacer()
                        }
                        .padding(.top, 8)
                        // Mode selection menu
                        Text("Choose Mode")
                            .font(.largeTitle.bold())
                            .foregroundColor(.white)

                        VStack(spacing: 16) {
                            Button {
                                selectMode(.easy, screenSize: geometry.size)
                            } label: {
                                Text("Easy")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 32)
                                    .padding(.vertical, 12)
                                    .background(Color.white)
                                    .cornerRadius(12)
                            }

                            Button {
                                selectMode(.difficult, screenSize: geometry.size)
                            } label: {
                                Text("Difficult")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 32)
                                    .padding(.vertical, 12)
                                    .background(Color.white)
                                    .cornerRadius(12)
                            }
                        }

                        Text("Easy: cat slows down when getting closer to the target.\nDifficult: cat responds directly to tilt (more twitchy).")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                } else {
                    // Game view
                    VStack {
                        // Top bar with back button
                        HStack {
                            Button {
                                endGameSession(resetToMenu: true)
                            } label: {
                                Text("Back")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(8)
                            }

                            Spacer()
                        }
                        .padding([.top, .horizontal], 16)

                        if !gameOver, gameEndDeadline != nil {
                            timeRemainingBar
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }

                        Spacer()

                        // Game layer
                        ZStack {
                            // The laser pointer: bright center, edge fades to black so it blends with background
                            Circle()
                                .fill(
                                    RadialGradient(
                                        gradient: Gradient(stops: [
                                            .init(color: laserColor, location: 0),
                                            .init(color: laserColor, location: 0.35),
                                            .init(color: .black, location: 1.0)
                                        ]),
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: laserRadius
                                    )
                                )
                                .frame(width: laserRadius * 2, height: laserRadius * 2)
                                .position(laserPosition)

                            // The Cat Face from asset catalog
                            Image("cat_face")
                                .resizable()
                                .scaledToFit()
                                .frame(width: catSize, height: catSize)
                                .position(catPosition)
                                .shadow(color: .white.opacity(0.3), radius: 10)

                            if gameOver {
                                Color.black.opacity(0.55)
                                    .ignoresSafeArea()
                                VStack(spacing: 12) {
                                    Text("Game Over")
                                        .font(.title2.bold())
                                        .foregroundColor(.white)
                                    Text("Total hits: \(hitCount)")
                                        .font(.title.bold())
                                        .foregroundColor(.white)
                                }
                                .padding(28)
                                .background(Color.black.opacity(0.75))
                                .cornerRadius(16)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Score HUD at bottom
                        VStack(spacing: 4) {
                            Text("Hits: \(hitCount)")
                                .font(.headline)
                                .foregroundColor(.white)

                            Text("Avg time: \(formattedAverageInterval())")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(12)
                        .padding(.bottom, 24)
                    }
                }
            }
            .onAppear {
                // Cache screen size for later use when selecting mode
                screenSize = geometry.size
                configureAudioSession()
                // Load sound effect
                if let url = Bundle.main.url(forResource: "mixkit-short-laser-gun-shot-1670", withExtension: "wav") {
                    catchSoundPlayer = try? AVAudioPlayer(contentsOf: url)
                    catchSoundPlayer?.prepareToPlay()
                }
                #if os(iOS)
                // Apply user's chosen orientation so start screen appears in the right orientation
                applyPreferredOrientation()
                #endif
            }
            .onChange(of: geometry.size) { _, newSize in
                // Keep screen size in sync with device rotation so movement bounds stay correct
                screenSize = newSize
            }
        }
    }

    #if os(iOS)
    /// Applies the user-chosen orientation so the start screen and game use it. Call when the start screen appears and when the user taps the rotation button.
    private func applyPreferredOrientation() {
        let orientations: UIInterfaceOrientationMask = OrientationPreference.mask
        // Notify the system to re-query supported orientations (from AppDelegate) so rotation can take effect.
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }),
           let rootVC = window.rootViewController {
            rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        if #available(iOS 16.0, *) {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
            }
        }
    }
    #endif

    /// Map attitude to screen X/Y using the chosen orientation only (portrait or landscape right).
    private func tiltForScreen(from attitude: CMAttitude) -> (x: CGFloat, y: CGFloat) {
        let roll = CGFloat(attitude.roll)
        let pitch = CGFloat(attitude.pitch)
        #if os(iOS)
        if OrientationPreference.isLandscape {
            // Landscape right: device is rotated 90° CW; screen X = forward tilt (pitch), screen Y = side tilt (roll).
            return (x: pitch, y: roll*(-1))
        }
        #endif
        // Portrait: roll = left/right → X, pitch = forward/back → Y.
        return (x: roll, y: pitch)
    }

    // Called when the user picks Easy or Difficult mode from the menu
    private func selectMode(_ mode: MovementMode, screenSize: CGSize) {
        movementMode = mode
        self.screenSize = screenSize

        // Reset game state for the new session
        catPosition = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
        laserPosition = randomLaserPosition(in: screenSize)
        laserColor = .red
        isLaserHit = false
        hitCount = 0
        lastHitDate = nil
        totalHitInterval = 0
        lastSignificantMovementDate = Date()
        gameOver = false
        gameEndDeadline = Date().addingTimeInterval(roundTimeSeconds)

        startMotionUpdates(screenSize: screenSize, mode: mode)

        // Keep screen on while the game is active; let a timer manage it based on movement
        #if os(iOS)
        startIdleTimer()
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
    }
    
    func startMotionUpdates(screenSize: CGSize, mode: MovementMode) {
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1/60
            motion.startDeviceMotionUpdates(to: .main) { data, _ in
                guard !gameOver else { return }
                if let end = gameEndDeadline, Date() >= end {
                    endGameSession(resetToMenu: false)
                    return
                }
                guard let attitude = data?.attitude else { return }

                let tilt = tiltForScreen(from: attitude)

                switch mode {
                case .easy:
                    // Move towards a target position based on tilt
                    // Easier fine-tuning when close to the movement target
                    let targetX = (screenSize.width / 2) + (tilt.x * sensitivity * 20)
                    let targetY = (screenSize.height / 2) + (tilt.y * sensitivity * 20)
                    
                    withAnimation(.interactiveSpring()) {
                        catPosition.x += (targetX - catPosition.x) * damping
                        catPosition.y += (targetY - catPosition.y) * damping
                        
                        // Keep the cat on screen (using a fixed margin similar to original)
                        let margin: CGFloat = 25
                        catPosition.x = min(max(catPosition.x, margin), screenSize.width - margin)
                        catPosition.y = min(max(catPosition.y, margin), screenSize.height - margin)
                    }
                    
                case .difficult:
                    // Velocity-based movement: more direct response to tilt
                    let velocityX = tilt.x * sensitivity * 8
                    let velocityY = tilt.y * sensitivity * 8
                    
                    // Apply damping to velocity for smooth movement
                    let dampedVelocityX = velocityX * damping
                    let dampedVelocityY = velocityY * damping
                    
                    // Calculate new position based on velocity
                    let newX = catPosition.x + dampedVelocityX
                    let newY = catPosition.y + dampedVelocityY
                    
                    // Keep the cat on screen (clamp after movement calculation)
                    let margin = catSize / 2
                    let clampedX = min(max(newX, margin), screenSize.width - margin)
                    let clampedY = min(max(newY, margin), screenSize.height - margin)
                    
                    withAnimation(.interactiveSpring()) {
                        catPosition.x = clampedX
                        catPosition.y = clampedY
                    }
                }

                // Track significant movement by gyro (rotation rate), not tilt — phone can be tilted but still
                #if os(iOS)
                if let rot = data?.rotationRate {
                    let gyroMagnitude = sqrt(rot.x * rot.x + rot.y * rot.y + rot.z * rot.z)
                    if gyroMagnitude > movementThresholdGyro {
                        lastSignificantMovementDate = Date()
                    }
                }
                #endif

                // Check proximity between cat and laser
                let dx = catPosition.x - laserPosition.x
                let dy = catPosition.y - laserPosition.y
                let distance = sqrt(dx * dx + dy * dy)

                // Threshold: roughly overlap of cat and laser circles
                let hitThreshold = (catSize / 2) + laserRadius * 0.5

                if distance < hitThreshold && !isLaserHit {
                    handleLaserHit(screenSize: screenSize)
                }
            }
        }
    }

    #if os(iOS)
    // Start the timer that manages the idle timer (screen lock) based on movement
    // This timer is separate from the motion update timer to avoid conflicts
    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard movementMode != nil else {
                UIApplication.shared.isIdleTimerDisabled = false
                return
            }

            let now = Date()
            if let lastMove = lastSignificantMovementDate,
               now.timeIntervalSince(lastMove) <= 5 {  // Enable screen lock timer after 5 s
                UIApplication.shared.isIdleTimerDisabled = true
            } else {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        RunLoop.main.add(idleTimer!, forMode: .common)
    }
    #endif

    // When the cat reaches the laser: flash green, then teleport
    private func handleLaserHit(screenSize: CGSize) {
        guard !gameOver, let end = gameEndDeadline else { return }
        gameEndDeadline = end.addingTimeInterval(bonusSecondsPerHit)
        isLaserHit = true
        laserColor = .green
        if soundEnabled {
            catchSoundPlayer?.currentTime = 0
            catchSoundPlayer?.play()
        }

        // Update score and timing
        let now = Date()
        if let last = lastHitDate {
            let interval = now.timeIntervalSince(last)
            totalHitInterval += interval
            hitCount += 1
        } else {
            // First hit: start timing, count as first hit but no interval yet
            hitCount = 1
        }
        lastHitDate = now

        // After 0.5 seconds, reset color and move to new random location
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            laserColor = .red
            laserPosition = randomLaserPosition(in: screenSize)
            isLaserHit = false
        }
    }

    /// Use .playback so game sound is controlled only by the in-app toggle, not the phone silent switch.
    private func configureAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
        #endif
    }

    // Generate a random on-screen position for the laser, keeping it inside margins
    private func randomLaserPosition(in size: CGSize) -> CGPoint {
        // Extra margin so the laser never appears too close to the edges
        // and remains comfortably reachable by the cat.
        let extraPadding: CGFloat = catSize
        let margin = laserRadius + 10 + extraPadding
        let xRange = margin...(size.width - margin)
        let yRange = margin...(size.height - margin)

        let x = CGFloat.random(in: xRange)
        let y = CGFloat.random(in: yRange)

        return CGPoint(x: x, y: y)
    }

    // Format the average interval between hits as a short string
    private func formattedAverageInterval() -> String {
        // Need at least 2 hits to have an interval
        guard hitCount > 1, totalHitInterval > 0 else {
            return "--"
        }

        let average = totalHitInterval / Double(hitCount - 1)

        if average < 10 {
            // Show with one decimal for short times
            return String(format: "%.1f s", average)
        } else {
            // Round to whole seconds for longer times
            return String(format: "%.0f s", average)
        }
    }

    /// Stops motion and timers. If `resetToMenu`, returns to the mode picker; otherwise ends the round in place (timer expired).
    private func endGameSession(resetToMenu: Bool) {
        motion.stopDeviceMotionUpdates()
        gameEndDeadline = nil
        if resetToMenu {
            gameOver = false
            movementMode = nil
        } else {
            gameOver = true
        }
        #if os(iOS)
        idleTimer?.invalidate()
        idleTimer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
    }

    private var timeRemainingBar: some View {
        Group {
            if let end = gameEndDeadline {
                TimelineView(.periodic(from: .now, by: 0.05)) { context in
                    let remaining = max(0, end.timeIntervalSince(context.date))
                    let fill = min(1.0, remaining / roundTimeSeconds)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                            Capsule()
                                .fill(Color.orange.opacity(0.95))
                                .frame(width: max(0, geo.size.width * CGFloat(fill)))
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }
}
