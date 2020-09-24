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
    private var scheduledWorkItems: [String: [DispatchWorkItem]] = [:]

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
        statusBarItem.button?.title = event
            .displayString(includingDuration: preferences.showEventDuration)

        scheduleRefresh()
    }

    func scheduleRefresh() {
        eventStore.attempt { eventStore -> AnyBidirectionalCollection<EKEvent> in
            eventStore.availableEvents()
        } completion: { result in
            switch result {
            case let .success(events):
                self.pruneScheduledWorkItems(for: events)

                events.forEach { event in
                    self.cancelWorkItems(for: event)

                    if event.startDate.timeIntervalSinceNow > 0 {
                        let delay = max(1, event.startDate.addingTimeInterval(-60).timeIntervalSinceNow)
                        self.scheduleWorkItem(for: event, after: delay) { [weak self] in
                            self?.update(with: event)
                        }
                    }

                    self.scheduleWorkItem(for: event, after: event.endDate.timeIntervalSinceNow + 1) { [weak self] in
                        self?.refresh()
                    }
                }
            case .failure:
                break
            }
        }
    }
}

private extension AppDelegate {
    func pruneScheduledWorkItems<C: Collection>(for events: C) where C.Element == EKEvent {
        let eventIds = Set(events.compactMap { $0.eventIdentifier })
        let scheduledEventIds = Set(scheduledWorkItems.keys)

        scheduledEventIds.subtracting(eventIds).forEach { key in
            self.scheduledWorkItems.removeValue(forKey: key)
        }
    }

    func cancelWorkItems(for event: EKEvent) {
        scheduledWorkItems[event.eventIdentifier]?.forEach {
            $0.cancel()
        }

        scheduledWorkItems[event.eventIdentifier]?.removeAll()
    }

    func scheduleWorkItem(for event: EKEvent, after delay: TimeInterval, _ work: @escaping () -> Void) {
        let workItem = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        scheduledWorkItems[event.eventIdentifier, default: []].append(workItem)
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

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makePreferenceToggleMenuItem(for: \.showEventDuration, title: "Event duration"))
        menu.addItem(makePreferenceToggleMenuItem(for: \.useSmallerFont, title: "Use a smaller font"))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(terminateApp), keyEquivalent: ""))
        return menu
    }

    func makePreferenceToggleMenuItem(for preference: WritableKeyPath<Preferences, Bool>, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performAssociatedBlock), keyEquivalent: "")
        item.representedObject = { [weak item] in
            self.preferences[keyPath: preference].toggle()
            item?.state = self.preferences[keyPath: preference] ? .on : .off
        }
        item.state = preferences[keyPath: preference] ? .on : .off
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

        let mostRecentPresentEvent = presentEvents.max { lhs, rhs in
            lhs.startDate < rhs.startDate
        }

        return mostRecentPresentEvent ?? futureEvents.first
    }

    func availableEvents(startingFrom startDate: Date = Date()) -> AnyBidirectionalCollection<EKEvent> {
        guard let endDate = Calendar.current.endOfDay(for: startDate) else {
            return AnyBidirectionalCollection([])
        }

        let predicate = predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let eligibleEvents = events(matching: predicate)
            .lazy
            .filter { !$0.isAllDay && $0.status != .canceled }
        return AnyBidirectionalCollection(eligibleEvents)
    }
}

private extension EKEvent {
    var isHappeningNow: Bool {
        (startDate...endDate).contains(Date())
    }

    func displayString(includingDuration duration: Bool) -> String {
        var components = [String]()

        if startDate.isWithinHour {
            let dateFormatter = RelativeDateTimeFormatter()
            dateFormatter.formattingContext = .beginningOfSentence
            components.append(dateFormatter.localizedString(for: startDate, relativeTo: Date()))
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
        (0..<(60 * 60)).contains(timeIntervalSinceNow)
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
