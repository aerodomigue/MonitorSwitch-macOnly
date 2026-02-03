//
//  DisplayService.swift
//  MonitorSwitchUI
//
//  Display control service for macOS
//

import Foundation
import CoreGraphics
import IOKit
import IOKit.pwr_mgt
import Combine
import AppKit

@MainActor
class DisplayService: ObservableObject {
    @Published private(set) var isDisplayOn: Bool = true
    
    private let displayStateSubject = CurrentValueSubject<Bool, Never>(true)
    
    var displayStatePublisher: AnyPublisher<Bool, Never> {
        displayStateSubject.eraseToAnyPublisher()
    }
    
    private var assertionID: IOPMAssertionID = 0
    
    init() {
        print("DisplayService initialized")
        
        // Get display count
        var displayCount: UInt32 = 0
        let result = CGGetActiveDisplayList(0, nil, &displayCount)
        print("Available displays: \(displayCount) (result: \(result))")
        
        if displayCount > 0 {
            var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
            CGGetActiveDisplayList(displayCount, &displays, nil)
            
            for (index, display) in displays.enumerated() {
                let bounds = CGDisplayBounds(display)
                print("Display \(index): ID=\(display), bounds=\(bounds)")
            }
        }
    }
    
    func turnOn() {
        print("DisplayService: turnOn() called")
        _ = wakeDisplays()
        isDisplayOn = true
        displayStateSubject.send(true)
    }
    
    func turnOff() {
        print("DisplayService: turnOff() called") 
        _ = sleepDisplays()
        isDisplayOn = false
        displayStateSubject.send(false)
    }
    
    func test() {
        print("Testing display control...")
        print("Turning off displays...")
        turnOff()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            print("Turning on displays...")
            self.turnOn()
        }
    }
    
    private func wakeDisplays() -> Bool {
        print("Attempting to wake displays...")
        
        // Use caffeinate command with user activity simulation
        print("Using caffeinate to wake displays...")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        task.arguments = ["-u", "-t", "1"] // -u simulates user activity, -t 1 for 1 second
        
        do {
            try task.run()
            task.waitUntilExit()
            print("Caffeinate command executed with exit code: \(task.terminationStatus)")
            if task.terminationStatus == 0 {
                return true
            }
        } catch {
            print("Failed to execute caffeinate command: \(error)")
        }
        
        // Fallback: Create display wake assertion
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "MonitorSwitchUI keeping display awake" as CFString,
            &assertionID
        )
        
        if result == kIOReturnSuccess {
            print("Successfully created display wake assertion as fallback")
            return true
        } else {
            print("Failed to create display wake assertion: \(result)")
        }
        
        return false
    }
    
    private func sleepDisplays() -> Bool {
        print("Attempting to sleep displays...")
        
        // Release any wake assertion first
        if assertionID != 0 {
            let releaseResult = IOPMAssertionRelease(assertionID)
            assertionID = 0
            print("Released wake assertion: \(releaseResult == kIOReturnSuccess ? "Success" : "Failed")")
        }
        
        // Use pmset command (most reliable)
        print("Using pmset displaysleepnow...")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        
        do {
            try task.run()
            task.waitUntilExit()
            print("pmset displaysleepnow executed with exit code: \(task.terminationStatus)")
            return task.terminationStatus == 0
        } catch {
            print("Failed to execute pmset command: \(error)")
            return false
        }
    }
    
    private func updateDisplayState() async {
        // Check if displays are active
        let displayCount = CGDisplayCount()
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        
        CGGetActiveDisplayList(displayCount, &activeDisplays, nil)
        
        // For simplicity, we'll consider displays "on" if the main display is active
        let mainDisplay = CGMainDisplayID()
        let displayIsOn = activeDisplays.contains(mainDisplay)
        
        isDisplayOn = displayIsOn
        displayStateSubject.send(displayIsOn)
    }
}