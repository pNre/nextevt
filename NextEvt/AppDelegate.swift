//
//  AppDelegate.swift
//  NextEvt
//
//  Created by Pierluigi D'Andrea on 16/09/2020.
//

import Cocoa
import EventKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var statusBarItem = makeStatusItem()
    private lazy var eventStore = EKEventStore()
    private var preferences = Preferences() {
        didSet {
            DispatchQueue.main.async {
                self.preferencesDidChange()
            }
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        refresh()

        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }
}

private extension AppDelegate {
    func refresh() {
        eventStore.attempt { eventStore in
            eventStore.nextEvent()
        } completion: { result in
            switch result {
            case let .success(event?):
                self.update(with: event)
            case .success:
                self.statusBarItem.button?.title = "・"
            case .failure(let error):
                self.statusBarItem.button?.title = "・"
                NSApplication.shared.presentError(error)
            }

            self.scheduleRefresh()
        }
    }

    func update(with event: EKEvent) {
        statusBarItem.menu = makeMenu(for: event)
        statusBarItem.button?.title = event
            .displayString(includingDuration: preferences.showEventDuration)
    }

    func scheduleRefresh() {
        eventStore.attempt { eventStore -> EKEvent? in
            eventStore.nextEvent()
        } completion: { result in
            switch result {
            case let .success(nextEvent?):
                let interval: Int
                if nextEvent.isHappeningNow,
                   nextEvent.endDate.timeIntervalSinceNow > 60 {
                    interval = 60
                } else if nextEvent.isHappeningNow {
                    interval = max(1, Int(nextEvent.endDate.timeIntervalSinceNow.rounded()))
                } else if nextEvent.startDate.timeIntervalSinceNow > 60 {
                    interval = 60
                } else {
                    interval = 1
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(interval)) {
                    self.refresh()
                }
            case .success:
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(30)) {
                    self.refresh()
                }
            case .failure:
                break
            }
        }
    }
}

private extension AppDelegate {
    func preferencesDidChange() {
        refresh()
        statusBarItem.button?.font = preferences.preferredStatusBarFont
    }
}

private extension AppDelegate {
    func makeStatusItem() -> NSStatusItem {
        let statusBar = NSStatusBar.system
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem.button?.title = "・"
        statusBarItem.button?.font = preferences.preferredStatusBarFont
        statusBarItem.button?.sendAction(on: .leftMouseUp)
        statusBarItem.menu = makeMenu()
        return statusBarItem
    }

    func makeMenu(for event: EKEvent? = nil) -> NSMenu {
        let menu = NSMenu()
        
        if let url = event?.detectVideoCallsURL().first {
            let item = NSMenuItem(title: "Join call", action: #selector(performAssociatedBlock), keyEquivalent: "")
            item.representedObject = { [weak self] () -> Void in
                guard let webBrowser = self?.preferences.webBrowser,
                      let webBrowserURL = NSWorkspace.shared.fullPath(forApplication: webBrowser).map(URL.init(fileURLWithPath:)) else {
                    NSWorkspace.shared.open(url)
                    return
                }
                
                NSWorkspace.shared.open(
                    [url],
                    withApplicationAt: webBrowserURL,
                    configuration: NSWorkspace.OpenConfiguration(),
                    completionHandler: nil
                )
            }
            menu.addItem(item)
            menu.addItem(.separator())
        }
        
        menu.addItem(makePreferenceToggleMenuItem(for: \.showEventDuration, title: "Event duration"))
        menu.addItem(makePreferenceToggleMenuItem(for: \.useSmallerFont, title: "Use a smaller font"))
        menu.addItem(.separator())
        menu.addItem(makeWebBrowserMenuItem())
        menu.addItem(makePreferenceToggleMenuItem(for: \.launchAtLogin, title: "Launch at login"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(terminateApp), keyEquivalent: ""))
        return menu
    }

    func makeWebBrowserMenuItem() -> NSMenuItem {
        let browsers = ["Safari", "Firefox", "Google Chrome"]
        let submenu = NSMenu()
        let item = NSMenuItem(title: "Join calls in", action: nil, keyEquivalent: "")
        item.submenu = submenu
        
        func updateSubmenu() {
            submenu.removeAllItems()
            
            browsers.forEach { browser in
                submenu.addItem(
                    makeValueToggleMenuItem(
                        for: \.webBrowser,
                        title: browser,
                        value: browser,
                        onSelect: updateSubmenu
                    )
                )
            }
        }
        
        updateSubmenu()
        
        return item
    }

    func makePreferenceToggleMenuItem(for preference: WritableKeyPath<Preferences, Bool>, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performAssociatedBlock), keyEquivalent: "")
        item.representedObject = { [weak self, weak item] in
            guard let self = self else {
                return
            }

            self.preferences[keyPath: preference].toggle()
            item?.state = self.preferences[keyPath: preference] ? .on : .off
        }
        item.state = preferences[keyPath: preference] ? .on : .off
        return item
    }

    func makeValueToggleMenuItem(
        for preference: WritableKeyPath<Preferences, String?>,
        title: String,
        value: String?,
        onSelect: @escaping () -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performAssociatedBlock), keyEquivalent: "")
        item.representedObject = { [weak self] in
            if self?.preferences[keyPath: preference] == value {
                self?.preferences[keyPath: preference] = nil
            } else {
                self?.preferences[keyPath: preference] = value
            }
            onSelect()
        }
        item.state = preferences[keyPath: preference] == value ? .on : .off
        return item
    }
}

private extension AppDelegate {
    @objc func terminateApp() {
        NSRunningApplication.current.terminate()
    }

    @objc func performAssociatedBlock(sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }
}

private extension EKEventStore {
    func attempt<T>(_ f: @escaping (EKEventStore) throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized:
            completion(Result(catching: { try f(self) }))
        case .notDetermined:
            requestAccess(to: .event) { granted, error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        completion(Result(catching: { try f(self) }))
                    }
                }
            }
        case .denied,
             .restricted:
            completion(.failure(RuntimeError("Calendar permission not granted")))
        @unknown default:
            completion(.failure(RuntimeError("Calendar permission not granted")))
        }
    }

    func nextEvent() -> EKEvent? {
        let events = availableEvents()
        let presentEvents = events.prefix { $0.isHappeningNow }
        let futureEvents = events.dropFirst(presentEvents.count)

        if let currentEvent = presentEvents.last,
           let nextEvent = futureEvents.first {
            let intervalBetweenEvents = nextEvent.startDate.timeIntervalSince(currentEvent.endDate)
            let intervalToCurrentEventEnd = currentEvent.endDate.timeIntervalSinceNow
            if intervalBetweenEvents >= 0,
               intervalToCurrentEventEnd > currentEvent.endDate.timeIntervalSince(currentEvent.startDate) / 2 {
                return currentEvent
            } else {
                return nextEvent
            }
        } else if let currentEvent = presentEvents.last {
            return currentEvent
        } else {
            return futureEvents.first
        }
    }

    func availableEvents(startingFrom startDate: Date = Date()) -> AnyBidirectionalCollection<EKEvent> {
        guard let endDate = Calendar.current.endOfDay(for: startDate) else {
            return AnyBidirectionalCollection([])
        }

        let predicate = predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let eligibleEvents = events(matching: predicate)
            .lazy
            .filter { !$0.isAllDay && $0.isCurrentUserAttending }
            .sorted { lhs, rhs in lhs.startDate < rhs.startDate }
        return AnyBidirectionalCollection(eligibleEvents)
    }
}

private extension EKEvent {
    var isHappeningNow: Bool {
        (startDate...endDate).contains(Date())
    }
    
    var isCurrentUserAttending: Bool {
        guard status != .canceled else {
            return false
        }

        guard let attendees = attendees else {
            return true
        }
    
        return !attendees.contains { participant in
            participant.isCurrentUser && participant.participantStatus == .declined
        }
    }

    func hasStarted(byAtLeast interval: TimeInterval) -> Bool {
        startDate.timeIntervalSinceNow < -interval
    }

    func displayString(includingDuration duration: Bool) -> String {
        var components = [String]()

        if startDate.isWithinHour {
            let dateFormatter = RelativeDateTimeFormatter()
            dateFormatter.formattingContext = .beginningOfSentence
            dateFormatter.dateTimeStyle = .named
            let now = Date()
            components.append(dateFormatter.localizedString(for: max(startDate, now), relativeTo: now))
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = .current
            dateFormatter.doesRelativeDateFormatting = true
            dateFormatter.timeStyle = .short
            dateFormatter.dateStyle = .none
            components.append(dateFormatter.string(from: startDate))
        }

        let eventDuration = endDate.timeIntervalSince(startDate)
        if duration, eventDuration > 0 {
            let dateComponentsFormatter = DateComponentsFormatter()
            dateComponentsFormatter.unitsStyle = .short
            dateComponentsFormatter.zeroFormattingBehavior = .dropAll
            if let formattedComponents = dateComponentsFormatter.string(from: eventDuration) {
                components.append("(\(formattedComponents))")
            }
        }

        components.append("–")
        components.append(title)

        return components.joined(separator: " ").truncated(to: 40)
    }
    
    func detectVideoCallsURL() -> [URL] {
        guard let notes = notes,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
    
        let matches = detector.matches(
            in: notes,
            options: [],
            range: NSRange(notes.startIndex..<notes.endIndex, in: notes)
        )
        
        return matches
            .compactMap { match in
                guard let range = Range(match.range, in: notes) else {
                    return nil
                }
                
                return URL(string: String(notes[range]))
            }
            .filter { url in
                guard let host = url.host else {
                    return false
                }
            
                return host.hasSuffix("meet.google.com")
                    || host.hasSuffix("zoom.us")
            }
    }
}

private extension String {
    func truncated(to length: Int) -> String {
        guard count > length else {
            return self
        }

        return String(prefix(length)) + "…"
    }
}

private extension Date {
    var isWithinHour: Bool {
        timeIntervalSinceNow < 60 * 60
    }
}

private extension Calendar {
    func endOfDay(for date: Date) -> Date? {
        self.date(byAdding: .init(day: 1), to: date)
            .map(startOfDay(for:))
            .map { $0.addingTimeInterval(-1) }
    }
}

private extension Preferences {
    var preferredStatusBarFont: NSFont {
        .menuBarFont(
            ofSize: NSFont.systemFontSize(
                for: useSmallerFont ? .small : .regular
            )
        )
    }
}
