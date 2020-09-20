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
                self.refresh()
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
    @objc func refresh() {
        eventStore.attempt { eventStore in
            eventStore.NextEvt()
        } completion: { result in
            switch result {
            case let .success(event?):
                self.statusBarItem.button?.title = event
                    .displayString(includingDuration: self.preferences.showEventDuration)
                self.scheduleRefresh(for: event)
            case .success:
                self.statusBarItem.button?.title = "・"
            case .failure(let error):
                self.statusBarItem.button?.title = "・"
                NSApplication.shared.presentError(error)
            }
        }
    }

    func scheduleRefresh(for event: EKEvent) {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        eventStore.attempt { eventStore -> Date? in
            eventStore.nextRefreshDate()
        } completion: { result in
            switch result {
            case let .success(nextDate?):
                self.perform(#selector(self.refresh), with: nil, afterDelay: nextDate.timeIntervalSinceNow)
            case .success,
                 .failure:
                break
            }
        }
    }
}

private extension AppDelegate {
    func makeStatusItem() -> NSStatusItem {
        let statusBar = NSStatusBar.system
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem.button?.title = "・"
        statusBarItem.button?.font = .menuBarFont(ofSize: NSFont.systemFontSize(for: .small))
        statusBarItem.button?.sendAction(on: .leftMouseUp)
        statusBarItem.menu = makeMenu()
        return statusBarItem
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makePreferenceToggleMenuItem(for: \.showEventDuration, title: "Event duration"))
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
    func attempt<T>(_ task: @escaping (EKEventStore) throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized:
            do {
                completion(.success(try task(self)))
            } catch let error {
                completion(.failure(error))
            }
        case .notDetermined:
            requestAccess(to: .event) { granted, error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        do {
                            completion(.success(try task(self)))
                        } catch let error {
                            completion(.failure(error))
                        }
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

    func NextEvt() -> EKEvent? {
        let events = availableEvents()
        let presentEvents = events.prefix { $0.isHappeningNow }
        let futureEvents = events.dropFirst(presentEvents.count)

        if presentEvents.isEmpty {
            return futureEvents.first
        }

        return presentEvents.max { lhs, rhs in
            lhs.startDate < rhs.startDate
        }
    }

    func nextRefreshDate() -> Date? {
        availableEvents()
            .flatMap { [$0.startDate, $0.endDate] }
            .filter { $0.timeIntervalSinceNow > 0 }
            .min()
            .map { date in
                guard date.isWithinHour else {
                    return date
                }

                guard date.timeIntervalSinceNow > 60 else {
                    return Date(timeIntervalSinceNow: 1)
                }

                return min(Date(timeIntervalSinceNow: 60), date)
            }
    }

    func availableEvents(withStart startDate: Date = Date()) -> AnyBidirectionalCollection<EKEvent> {
        let calendar = Calendar.current
        guard let endDate = calendar
                .date(byAdding: .init(day: 1), to: startDate)
                .map(calendar.startOfDay(for:))
                .map({ $0.addingTimeInterval(-1) }) else {
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
