//
//  ContentView.swift
//  balance_ball
//
//  Created by Lin Zhou on 08.02.26.
//

import SwiftUI
import CoreMotion
import AVFoundation

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
    
    // 2. Sensitivity Settings (Adjust these for your balance board!)
    let sensitivity: CGFloat = 50.0
    let damping: CGFloat = 0.15 // Lower = smoother/slower, Higher = twitchier
    let laserRadius: CGFloat = 25.0
    let catSize: CGFloat = 60.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                if movementMode == nil {
                    // Mode selection menu
                    VStack(spacing: 24) {
                        Text("Choose Mode")
                            .font(.largeTitle.bold())
                            .foregroundColor(.white)

                        VStack(spacing: 16) {
                            Button {
                                selectMode(.easy, screenSize: geometry.size)
                            } label: {
                                Text("Easy Mode")
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
                                Text("Difficult Mode")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 32)
                                    .padding(.vertical, 12)
                                    .background(Color.white)
                                    .cornerRadius(12)
                            }
                        }

                        Text("Easy: cat moves based on distance to target.\nDifficult: cat responds directly to tilt (more twitchy).")
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
                                motion.stopDeviceMotionUpdates()
                                movementMode = nil
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
                
                // Load sound effect
                if let url = Bundle.main.url(forResource: "mixkit-short-laser-gun-shot-1670", withExtension: "wav") {
                    catchSoundPlayer = try? AVAudioPlayer(contentsOf: url)
                    catchSoundPlayer?.prepareToPlay()
                }
            }
        }
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

        startMotionUpdates(screenSize: screenSize, mode: mode)
    }
    
    func startMotionUpdates(screenSize: CGSize, mode: MovementMode) {
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1/60
            motion.startDeviceMotionUpdates(to: .main) { data, _ in
                guard let attitude = data?.attitude else { return }
                
                switch mode {
                case .easy:
                    // Move towards a target position based on tilt
                    // Easier fine-tuning when close to the movement target
                    // Pitch = Forward/Back, Roll = Left/Right
                    let targetX = (screenSize.width / 2) + (CGFloat(attitude.roll) * sensitivity * 30)
                    let targetY = (screenSize.height / 2) + (CGFloat(attitude.pitch) * sensitivity * 30)
                    
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
                    // Pitch = Forward/Back, Roll = Left/Right
                    let velocityX = CGFloat(attitude.roll) * sensitivity * 5
                    let velocityY = CGFloat(attitude.pitch) * sensitivity * 5
                    
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

    // When the cat reaches the laser: flash green, then teleport
    private func handleLaserHit(screenSize: CGSize) {
        isLaserHit = true
        laserColor = .green
        catchSoundPlayer?.currentTime = 0  //sound starts from 0 again
        catchSoundPlayer?.play()

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
}
