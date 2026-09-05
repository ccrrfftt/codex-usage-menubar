import AppKit
import Foundation
import IOKit.ps
import Network

/// System event subscriptions replace polling for power, display, and network state.
@MainActor
final class SystemActivityMonitor {
    private(set) var state = EnergyState()
    var onChange: (@MainActor (EnergyState) -> Void)?
    private var observations: [(NotificationCenter, NSObjectProtocol)] = []
    private var powerSource: CFRunLoopSource?
    private let pathMonitor = NWPathMonitor()
    private var stopped = false

    init() {
        updatePower()
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.systemSleeping = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.systemSleeping = false }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.displaySleeping = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.displaySleeping = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }

        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<SystemActivityMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.updatePower() }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor in self?.update { $0.networkAvailable = available } }
        }
        pathMonitor.start(queue: DispatchQueue(label: "local.codexusage.network", qos: .utility))
    }

    func stop() {
        stopped = true
        for (center, token) in observations { center.removeObserver(token) }
        observations.removeAll()
        if let powerSource { CFRunLoopSourceInvalidate(powerSource) }
        powerSource = nil
        pathMonitor.cancel()
        onChange = nil
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         change: @escaping @MainActor (inout EnergyState) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.update(change) }
        }
        observations.append((center, token))
    }

    private func update(_ change: (inout EnergyState) -> Void) {
        guard !stopped else { return }
        let previous = state
        change(&state)
        if state != previous { onChange?(state) }
    }

    private func updatePower() {
        update { state in
            if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
               let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
                state.onBattery = (source as String) != kIOPSACPowerValue
            }
        }
    }
}
