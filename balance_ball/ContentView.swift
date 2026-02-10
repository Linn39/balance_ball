//
//  ContentView.swift
//  balance_ball
//
//  Created by Lin Zhou on 08.02.26.
//

import SwiftUI
import CoreMotion

struct ContentView: View {
    // 1. Sensor & Position State
    @State private var ballPosition = CGPoint(x: 200, y: 400)
    @State private var motion = CMMotionManager()
    @State private var marblePosition = CGPoint(x: 150, y: 300)
    @State private var marbleColor: Color = .red
    @State private var isMarbleHit: Bool = false
    @State private var hitCount: Int = 0
    @State private var lastHitDate: Date? = nil
    @State private var totalHitInterval: TimeInterval = 0
    
    // 2. Sensitivity Settings (Adjust these for your balance board!)
    let sensitivity: CGFloat = 50.0
    let damping: CGFloat = 0.15 // Lower = smoother/slower, Higher = twitchier
    let marbleRadius: CGFloat = 25.0
    let catSize: CGFloat = 60.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // The "Floor"
                Color.black.ignoresSafeArea()

                // The Marble (laser pointer)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [marbleColor, .black],
                            center: .center,
                            startRadius: 0,
                            endRadius: marbleRadius
                        )
                    )
                    .frame(width: marbleRadius * 2, height: marbleRadius * 2)
                    .position(marblePosition)
                    .shadow(color: .white.opacity(0.3), radius: 8)

                // The Cat Face from asset catalog
                Image("cat_face")
                    .resizable()
                    .scaledToFit()
                    .frame(width: catSize, height: catSize)
                    .position(ballPosition)
                    .shadow(color: .white.opacity(0.3), radius: 10)

                // Score HUD at bottom
                VStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Hits: \(hitCount)")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("Avg time between hits: \(formattedAverageInterval())")
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
            .onAppear {
                // Place the marble at a random starting position
                marblePosition = randomMarblePosition(in: geometry.size)
                startMotionUpdates(screenSize: geometry.size)
            }
        }
    }
    
    func startMotionUpdates(screenSize: CGSize) {
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1/60
            motion.startDeviceMotionUpdates(to: .main) { data, _ in
                guard let attitude = data?.attitude else { return }
                
                // Calculate "Target" position based on tilt
                // Pitch = Forward/Back, Roll = Left/Right
                let targetX = (screenSize.width / 2) + (CGFloat(attitude.roll) * sensitivity * 10)
                let targetY = (screenSize.height / 2) + (CGFloat(attitude.pitch) * sensitivity * 10)
                
                // 3. Applying Smoothing (Linear Interpolation)
                // Instead of jumping to target, we move a small % towards it
                withAnimation(.interactiveSpring()) {
                    ballPosition.x += (targetX - ballPosition.x) * damping
                    ballPosition.y += (targetY - ballPosition.y) * damping
                    
                    // Keep the ball on screen
                    ballPosition.x = min(max(ballPosition.x, 25), screenSize.width - 25)
                    ballPosition.y = min(max(ballPosition.y, 25), screenSize.height - 25)

                    // Check proximity between cat and marble
                    let dx = ballPosition.x - marblePosition.x
                    let dy = ballPosition.y - marblePosition.y
                    let distance = sqrt(dx * dx + dy * dy)

                    // Threshold: roughly overlap of cat and marble circles
                    let hitThreshold = (catSize / 2) + marbleRadius * 0.5

                    if distance < hitThreshold && !isMarbleHit {
                        handleMarbleHit(screenSize: screenSize)
                    }
                }
            }
        }
    }

    // When the cat reaches the marble: flash green, then teleport
    private func handleMarbleHit(screenSize: CGSize) {
        isMarbleHit = true
        marbleColor = .green

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
            marbleColor = .red
            marblePosition = randomMarblePosition(in: screenSize)
            isMarbleHit = false
        }
    }

    // Generate a random on-screen position for the marble, keeping it inside margins
    private func randomMarblePosition(in size: CGSize) -> CGPoint {
        let margin = marbleRadius + 10
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
