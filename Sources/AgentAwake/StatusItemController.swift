import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let appController: AppController

    init(appController: AppController) {
        self.appController = appController
        self.statusItem = NSStatusBar.system.statusItem(
            withLength: 31
        )
        self.popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()

        appController.onStatusChange = { [weak self] in
            self?.updateStatusIcon()
        }
        updateStatusIcon()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 340, height: 290)
        popover.contentViewController = NSHostingController(
            rootView: StatusPopoverView(appController: appController)
        )
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else {
            return
        }

        let isActive = appController.isEnabled
        let tintColor = isActive
            ? NSColor.white
            : NSColor(calibratedWhite: 0.62, alpha: 1)
        let image = SleepStatusIcon.makeImage(
            color: tintColor,
            accessibilityDescription: isActive
                ? "防休眠功能已开启"
                : "防休眠功能已关闭"
        )
        button.image = image
        button.contentTintColor = nil
        if appController.isProtecting {
            button.toolTip = "AgentAwake · 正在防休眠"
        } else if appController.isEnabled {
            button.toolTip = "AgentAwake · 等待 Agent"
        } else {
            button.toolTip = "AgentAwake · 已关闭"
        }
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }

        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else {
            return
        }

        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
    }
}
