import AppKit

/// Standard native commands for both Mac hosts. Editing stays on the responder
/// chain, and Quit enters NSApplication's delegate-mediated recovery path.
@MainActor
enum MacMainMenu {
    static func install(on application: NSApplication, delegate: AppDelegate) {
        let main = NSMenu()
        let appMenu = submenu("Flowmo", in: main)
        item("Hide Flowmo", action: #selector(NSApplication.hide(_:)), key: "h", target: application, in: appMenu)
        let hideOthers = item(
            "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), key: "h",
            target: application, in: appMenu)
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        item("Show All", action: #selector(NSApplication.unhideAllApplications(_:)), target: application, in: appMenu)
        appMenu.addItem(.separator())
        item("Quit Flowmo", action: #selector(NSApplication.terminate(_:)), key: "q", target: application, in: appMenu)

        let editMenu = submenu("Edit", in: main)
        item("Undo", action: Selector(("undo:")), key: "z", in: editMenu)
        let redo = item("Redo", action: Selector(("redo:")), key: "z", in: editMenu)
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        item("Cut", action: #selector(NSText.cut(_:)), key: "x", in: editMenu)
        item("Copy", action: #selector(NSText.copy(_:)), key: "c", in: editMenu)
        item("Paste", action: #selector(NSText.paste(_:)), key: "v", in: editMenu)
        item("Select All", action: #selector(NSText.selectAll(_:)), key: "a", in: editMenu)

        let windowMenu = submenu("Window", in: main)
        // A borderless Scene has no native close button. Route through the
        // existing window subclass so its guarded Close handler still runs.
        item("Close", action: #selector(AppDelegate.closeMainWindow(_:)), key: "w", target: delegate, in: windowMenu)
        item("Minimize", action: #selector(NSWindow.performMiniaturize(_:)), key: "m", in: windowMenu)
        windowMenu.addItem(.separator())
        item(
            "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), target: application,
            in: windowMenu)
        application.mainMenu = main
        application.windowsMenu = windowMenu
    }

    private static func submenu(_ title: String, in main: NSMenu) -> NSMenu {
        let menu = NSMenu(title: title)
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.submenu = menu
        main.addItem(entry)
        return menu
    }

    @discardableResult
    private static func item(
        _ title: String, action: Selector, key: String = "", target: AnyObject? = nil, in menu: NSMenu
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        item.keyEquivalentModifierMask = .command
        menu.addItem(item)
        return item
    }
}
