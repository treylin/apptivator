//
//  ViewController.swift
//  Apptivator
//

import MASShortcut
import LaunchAtLogin

let toggleWindowShortcutKey = "__Apptivator_global_show__"

class ViewController: NSViewController {

    var addMenu: NSMenu = NSMenu()
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var addButton: NSButton!
    @IBOutlet weak var removeButton: NSButton!
    @IBOutlet weak var appDelegate: AppDelegate!
    @IBOutlet weak var toggleWindowShortcut: MASShortcutView!

    // Local configuration values.
    @IBOutlet weak var hideWithShortcutWhenActive: NSButton!
    @IBOutlet weak var showOnScreenWithMouse: NSButton!
    @IBOutlet weak var hideWhenDeactivated: NSButton!
    @IBOutlet weak var launchIfNotRunning: NSButton!
    func getLocalConfigButtons() -> [NSButton] {
        return [
            hideWithShortcutWhenActive!,
            showOnScreenWithMouse!,
            hideWhenDeactivated!,
            launchIfNotRunning!
        ]
    }

    // Global configuration values.
    @IBOutlet weak var launchAppAtLogin: NSButton!

    @IBAction func onLocalCheckboxChange(_ sender: NSButton) {
        for index in tableView.selectedRowIndexes {
            let entry = state.entries[index]
            for button in getLocalConfigButtons() {
                entry.config[button.identifier!.rawValue] = button.state == .on ? true : false
            }
        }
    }

    @IBAction func onGlobalCheckboxChange(_ sender: NSButton) {
        let flag = sender.state == .on
        if let identifier = sender.identifier?.rawValue {
            if identifier == "launchAppAtLogin" {
                LaunchAtLogin.isEnabled = flag
            } else {
                print("Unknown identifier found: \(identifier)")
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.delegate = self
        tableView.dataSource = self

        addMenu.delegate = self
        addMenu.addItem(NSMenuItem(title: "Choose from File System", action: #selector(chooseFromFileSystem), keyEquivalent: ""))
        addMenu.addItem(NSMenuItem(title: "Choose from Running Applications", action: nil, keyEquivalent: ""))
        addMenu.item(at: 1)?.submenu = NSMenu()

        toggleWindowShortcut.associatedUserDefaultsKey = toggleWindowShortcutKey
        toggleWindowShortcut.shortcutValueChange = { (_: MASShortcutView?) in
            MASShortcutBinder.shared().bindShortcut(withDefaultsKey: toggleWindowShortcutKey, toAction: { self.appDelegate.togglePreferencesWindow() })
        }
        toggleWindowShortcut.shortcutValueChange(toggleWindowShortcut)
    }

    override func viewWillDisappear() {
        state.saveToDisk()
    }

    func reloadView() {
        tableView.reloadData()
        launchAppAtLogin.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @IBAction func onAddClick(_ sender: NSButton) {
        addMenu.popUp(positioning: addMenu.item(at: 0), at: NSEvent.mouseLocation, in: nil)
    }

    @IBAction func onRemoveClick(_ sender: NSButton) {
        let selected = tableView.selectedRow
        if selected >= 0 {
            let entry = state.entries.remove(at: selected)
            MASShortcutBinder.shared().breakBinding(withDefaultsKey: entry.key)
            tableView.reloadData()
        }
    }
    
    @objc func chooseFromRunningApps(_ sender: NSMenuItem) {
        guard let app = sender.representedObject else {
            return
        }

        if let url = (app as! NSRunningApplication).bundleURL {
            addEntry(fromURL: url)
        } else if let url = (app as! NSRunningApplication).executableURL {
            addEntry(fromURL: url)
        }
    }

    @objc func chooseFromFileSystem() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = NSURL.fileURL(withPath: "/Applications")
        panel.runModal()

        if let url = panel.url {
            addEntry(fromURL: url)
        }
    }

    func addEntry(fromURL url: URL) {
        // Check if the entry already exists.
        if let app = (state.entries.first { $0.url == url }) {
            let alert = NSAlert()
            alert.messageText = "Duplicate Entry"
            alert.informativeText = "The application \"\(app.name)\" has already been added. Please edit its entry in the list, or remove it to add it again."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        if let appEntry = ApplicationEntry(url: url, config: nil) {
            state.entries.append(appEntry)
            tableView.reloadData()
        }
    }
}

extension ViewController: NSMenuDelegate {
    // Populate context menu with a list of running apps when it's highlighted.
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard let item = item, item == addMenu.item(at: 1) else {
            addMenu.item(at: 1)?.submenu?.removeAllItems()
            return
        }

        let runningAppsMenu = item.submenu!
        for runningApp in NSWorkspace.shared.runningApplications {
            if runningApp.activationPolicy == .regular {
                let appItem = NSMenuItem(title: runningApp.localizedName!, action: #selector(chooseFromRunningApps(_:)), keyEquivalent: "")
                appItem.image = runningApp.icon
                appItem.representedObject = runningApp
                runningAppsMenu.addItem(appItem)
            }
        }
        item.submenu = runningAppsMenu
    }

    func menuDidClose(_ menu: NSMenu) {
        addMenu.item(at: 1)?.submenu?.removeAllItems()
    }
}

extension ViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return state.entries.count
    }
}

extension ViewController: NSTableViewDelegate {
    fileprivate enum CellIdentifiers {
        static let ApplicationCell = "ApplicationCellID"
        static let ShortcutCell = "ShortcutCellID"
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        var localConfig = getLocalConfigButtons().map { ($0, nil as NSControl.StateValue?) }

        // Return and disable checkboxes if no rows are selected.
        let selectedIndexes = tableView.selectedRowIndexes
        if selectedIndexes.count < 1 {
            for (button, _) in localConfig {
                button.state = .off
                button.isEnabled = false
            }
            return
        }

        // Combine settings together: if one app has a flag on, and another off, then the checkbox
        // state will be `.mixed`.
        for index in selectedIndexes {
            let entry = state.entries[index]
            for (i, tuple) in localConfig.enumerated() {
                let (button, newState) = tuple
                let entryValue = entry.config[button.identifier!.rawValue]!
                if newState == nil {
                    localConfig[i].1 = entryValue ? .on : .off
                } else if newState == .on && !entryValue || newState == .off && entryValue {
                    localConfig[i].1 = .mixed
                }
            }
        }

        // Apply new states.
        for (button, newState) in localConfig {
            button.state = newState!
            button.isEnabled = true
        }
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        if tableView.sortDescriptors[0].ascending {
            state.entries.sort { $0.name.lowercased() < $1.name.lowercased() }
        } else {
            state.entries.sort { $0.name.lowercased() > $1.name.lowercased() }
        }
        tableView.reloadData()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = state.entries[row]

        // Application column:
        if tableColumn == tableView.tableColumns[0] {
            if let cell = tableView.makeView(withIdentifier: .init(CellIdentifiers.ApplicationCell), owner: nil) as? NSTableCellView {
                cell.textField?.stringValue = item.name
                cell.imageView?.image = item.icon
                cell.toolTip = item.url.path
                return cell
            }
        }

        // Shortcut column:
        if tableColumn == tableView.tableColumns[1] {
            return item.shortcutCell
        }

        return nil
    }
}
