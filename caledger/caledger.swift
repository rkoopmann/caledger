//
//  Caledger.swift
//  caledger
//
//  Created by Richard Koopmann on 1/5/26.
//
//  A CLI tool for reading and formatting calendar entries from macOS Calendar.
//  Outputs events in a ledger-compatible format with support for filtering,
//  date ranges, and title mappings.
//

import ArgumentParser
import EventKit
import Foundation

// MARK: - Config

/// Configuration loaded from ~/.caledger
///
/// The config file uses a simple key=value format:
/// ```
/// # Settings
/// calendar = Work, Personal, Family
/// start = -1m
/// end = +0d
/// filter = wb
/// notes
/// notag
/// nomap
///
/// # Title mappings (any unrecognized key becomes a mapping)
/// wb12345 = expenses:travel:client
/// ```
struct Config {
    var calendars: [String] = []  // Default calendar names (empty = all calendars)
    var start: String?            // Default start date/offset
    var end: String?              // Default end date/offset
    var filter: String?           // Default title filter
    var notes: Bool?              // Default for -n flag (nil = use CLI default)
    var tag: Bool?                // Default for -t flag (nil = use CLI default)
    var nomap: Bool?              // Default for --nomap flag (nil = use CLI default)
    var dateBreak: Bool?          // Default for -b/--break flag (nil = use CLI default)
    var mappings: [String: String] = [:]  // Event title -> replacement mappings
    var duplicateMappingKeys: [String] = []  // Keys that appeared more than once

    static let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".caledger")

    /// Load configuration from ~/.caledger
    /// Returns default config if file doesn't exist or can't be read
    static func load() -> Config {
        var config = Config()

        guard let contents = try? String(contentsOf: configPath, encoding: .utf8) else {
            return config
        }

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix(";") { continue }

            // Handle boolean flags (no = sign): notes, nonotes, tag, notag, map, nomap, break, nobreak
            if !trimmed.contains("=") {
                switch trimmed {
                case "notes": config.notes = true
                case "nonotes": config.notes = false
                case "tag": config.tag = true
                case "notag": config.tag = false
                case "map": config.nomap = false
                case "nomap": config.nomap = true
                case "break": config.dateBreak = true
                case "nobreak": config.dateBreak = false
                default: break
                }
                continue
            }

            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            // Known keys become settings; everything else is a title mapping
            switch key {
            case "calendar":
                // Parse comma-separated calendar names
                config.calendars = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            case "start": config.start = value
            case "end": config.end = value
            case "filter": config.filter = value
            default:
                // Track duplicate mapping keys
                if config.mappings[key] != nil && !config.duplicateMappingKeys.contains(key) {
                    config.duplicateMappingKeys.append(key)
                }
                config.mappings[key] = value
            }
        }

        return config
    }

    /// Replace event title with mapped value if an exact match exists
    func mapTitle(_ title: String) -> String {
        mappings[title] ?? title
    }
}

// MARK: - Main Command

@main
struct Caledger: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "caledger",
        abstract: "A tool for reading calendar entries",
        subcommands: [List.self, Map.self],
        defaultSubcommand: List.self
    )
}

// MARK: - Map Command

/// Manage title mappings in the config file
struct Map: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "map",
        abstract: "Manage title mappings",
        subcommands: [MapList.self, MapAdd.self, MapRemove.self],
        defaultSubcommand: MapList.self
    )
}

/// List all title mappings from config
struct MapList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List all title mappings"
    )

    @Option(name: .shortAndLong, help: "Filter mappings by key or value (case-insensitive)")
    var filter: String?

    func run() throws {
        let config = Config.load()

        if config.mappings.isEmpty {
            print("No mappings defined in ~/.caledger")
            return
        }

        var mappings = config.mappings.sorted(by: { $0.key < $1.key })

        // Apply filter if specified
        if let filterStr = filter {
            mappings = mappings.filter { key, value in
                key.localizedCaseInsensitiveContains(filterStr) ||
                value.localizedCaseInsensitiveContains(filterStr)
            }
        }

        if mappings.isEmpty {
            print("No mappings match '\(filter!)'")
            return
        }

        for (key, value) in mappings {
            print("\(key) = \(value)")
        }

        // Warn about duplicate keys
        if !config.duplicateMappingKeys.isEmpty {
            let keys = config.duplicateMappingKeys.sorted().joined(separator: ", ")
            print("### Duplicate mappings found (last value used): \(keys)")
        }
    }
}

/// Add or update a title mapping
struct MapAdd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add or update a title mapping"
    )

    @Argument(help: "Event title to match")
    var key: String

    @Argument(help: "Replacement value")
    var value: String

    func run() throws {
        let configPath = Config.configPath
        var lines: [String] = []

        // Read existing config if it exists
        if let contents = try? String(contentsOf: configPath, encoding: .utf8) {
            lines = contents.components(separatedBy: .newlines)
        }

        // Check if key already exists and update it
        var found = false
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(key) =") || trimmed.hasPrefix("\(key)=") {
                lines[i] = "\(key) = \(value)"
                found = true
                break
            }
        }

        // If not found, append new mapping
        if !found {
            // Remove trailing empty lines before appending
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.removeLast()
            }
            lines.append("\(key) = \(value)")
        }

        // Write back to file
        let output = lines.joined(separator: "\n") + "\n"
        try output.write(to: configPath, atomically: true, encoding: .utf8)

        print(found ? "Updated: \(key) = \(value)" : "Added: \(key) = \(value)")
    }
}

/// Remove a title mapping
struct MapRemove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Remove a title mapping"
    )

    @Argument(help: "Event title mapping to remove")
    var key: String

    func run() throws {
        let configPath = Config.configPath

        guard let contents = try? String(contentsOf: configPath, encoding: .utf8) else {
            print("Config file not found: ~/.caledger")
            throw ExitCode.failure
        }

        var lines = contents.components(separatedBy: .newlines)
        let originalCount = lines.count

        // Remove lines that match the key
        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("\(key) =") || trimmed.hasPrefix("\(key)=")
        }

        if lines.count == originalCount {
            print("Mapping '\(key)' not found")
            throw ExitCode.failure
        }

        // Write back to file
        let output = lines.joined(separator: "\n")
        try output.write(to: configPath, atomically: true, encoding: .utf8)

        print("Removed: \(key)")
    }
}

// MARK: - List Subcommand

/// Lists calendar events in ledger-compatible format
///
/// Output format:
/// ```
/// i YYYY-MM-DD HH:MM:SS title    notes (if -n)
/// ; :CalendarName: (if -t)
/// o YYYY-MM-DD HH:MM:SS
/// ```
struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List calendar events"
    )

    // MARK: Options

    @Option(name: .shortAndLong, help: "Calendar name(s) to read from (repeatable, default: all calendars)")
    var calendar: [String] = []

    @Option(name: .shortAndLong, help: "Start date (YYYY-MM-DD or relative: -1y, -3m2w, +10d)")
    var start: String?

    @Option(name: .shortAndLong, help: "End date (YYYY-MM-DD or relative: +1y, -3m2w, +10d)")
    var end: String?

    @Option(name: .shortAndLong, help: "Filter events by title (case-insensitive contains)")
    var filter: String?

    @Flag(name: .shortAndLong, help: "Tag output with calendar name")
    var tag: Bool = false

    @Flag(name: .shortAndLong, help: "Include event notes appended to title")
    var notes: Bool = false

    @Flag(name: .long, help: "Skip title mappings from config")
    var nomap: Bool = false

    @Flag(name: .shortAndLong, help: "Add date headers between days")
    var `break`: Bool = false

    // MARK: Execution

    func run() async throws {
        let config = Config.load()

        // Command line options override config file values (CLI takes precedence if non-empty)
        let calendarNames = calendar.isEmpty ? config.calendars : calendar
        let startStr = start ?? config.start
        let endStr = end ?? config.end
        let titleFilter = filter ?? config.filter
        let includeNotes = notes || (config.notes ?? false)
        let includeTag = tag || (config.tag ?? false)
        let skipMapping = nomap || (config.nomap ?? false)
        let includeDateBreak = `break` || (config.dateBreak ?? false)

        // Request calendar access from macOS
        let granted = await CalendarService.requestAccess()

        guard granted else {
            print("Calendar access denied. Please grant access in System Settings > Privacy & Security > Calendars.")
            throw ExitCode.failure
        }

        // Resolve which calendars to read from
        let calendars: [EKCalendar]
        if calendarNames.isEmpty {
            // No calendars specified - use all available calendars
            calendars = CalendarService.allCalendars()
        } else {
            // Find each specified calendar
            var found: [EKCalendar] = []
            for name in calendarNames {
                guard let cal = CalendarService.findCalendar(named: name) else {
                    print("Calendar '\(name)' not found.")
                    print("Available calendars:")
                    for c in CalendarService.allCalendars() {
                        print("  - \(c.title)")
                    }
                    throw ExitCode.failure
                }
                found.append(cal)
            }
            calendars = found
        }

        // Fetch events within date range
        let (startDate, endDate) = parseDateRange(start: startStr, end: endStr)
        var events = CalendarService.fetchEvents(from: calendars, start: startDate, end: endDate)

        // Apply title filter if specified
        if let filterStr = titleFilter {
            events = events.filter {
                $0.title?.localizedCaseInsensitiveContains(filterStr) ?? false
            }
        }

        // Output events sorted chronologically
        var lastDate: String? = nil
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        let dayOfWeekFormatter = DateFormatter()
        dayOfWeekFormatter.dateFormat = "EEEE"

        for event in events.sorted(by: { $0.startDate < $1.startDate }) {
            // Add date header if date changed and break is enabled
            if includeDateBreak {
                let eventDate = dateOnlyFormatter.string(from: event.startDate)
                if eventDate != lastDate {
                    let dayOfWeek = dayOfWeekFormatter.string(from: event.startDate)
                    if lastDate != nil {
                        print("")  // Blank line before header (except first)
                    }
                    print("### \(eventDate) \(dayOfWeek) ###")
                    lastDate = eventDate
                }
            }

            print(CalendarService.formatEvent(event, config: config, includeCalendar: includeTag, includeNotes: includeNotes, skipMapping: skipMapping))
        }
    }

    // MARK: Date Parsing

    /// Parse start/end date strings, falling back to +/- 1 year from now
    func parseDateRange(start: String?, end: String?) -> (Date, Date) {
        let now = Date()
        let defaultStart = Calendar.current.date(byAdding: .year, value: -1, to: now)!
        let defaultEnd = Calendar.current.date(byAdding: .year, value: 1, to: now)!

        let startDate = start.flatMap { parseDate($0) } ?? defaultStart
        let endDate = end.flatMap { parseDate($0) } ?? defaultEnd

        return (startDate, endDate)
    }

    /// Parse a date string - tries absolute format first, then relative
    func parseDate(_ string: String) -> Date? {
        // Try absolute date first (YYYY-MM-DD)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if let date = dateFormatter.date(from: string) {
            return date
        }

        // Try relative date (+1y, -3m4d, etc.)
        return parseRelativeDate(string)
    }

    /// Parse relative date strings like "-3m4d" or "+1y2w"
    ///
    /// Supported units:
    /// - y: year
    /// - q: quarter (3 months)
    /// - m: month
    /// - w: week (7 days)
    /// - d: day
    func parseRelativeDate(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }

        var str = string
        let isNegative: Bool

        // Determine sign (default to positive/future)
        if str.hasPrefix("-") {
            isNegative = true
            str.removeFirst()
        } else if str.hasPrefix("+") {
            isNegative = false
            str.removeFirst()
        } else {
            isNegative = false
        }

        var result = Date()
        let calendar = Calendar.current

        // Parse number+unit pairs like "3m4d" -> [(3, "m"), (4, "d")]
        let pattern = /(\d+)([yqmwd])/
        let matches = str.matches(of: pattern)

        guard !matches.isEmpty else { return nil }

        for match in matches {
            guard let value = Int(match.1) else { continue }
            let unit = String(match.2)
            let signedValue = isNegative ? -value : value

            let component: Calendar.Component
            var multiplier = 1

            // Map unit character to Calendar.Component
            switch unit {
            case "y": component = .year
            case "q": component = .month; multiplier = 3  // Quarter = 3 months
            case "m": component = .month
            case "w": component = .day; multiplier = 7    // Week = 7 days
            case "d": component = .day
            default: continue
            }

            if let newDate = calendar.date(byAdding: component, value: signedValue * multiplier, to: result) {
                result = newDate
            }
        }

        return result
    }
}

// MARK: - Calendar Service

/// Wrapper around EventKit for calendar access and event formatting
enum CalendarService {
    static let eventStore = EKEventStore()

    /// Request full calendar access from macOS
    /// User will see a system permission prompt on first run
    static func requestAccess() async -> Bool {
        do {
            return try await eventStore.requestFullAccessToEvents()
        } catch {
            print("Error requesting calendar access: \(error.localizedDescription)")
            return false
        }
    }

    /// Find a calendar by name (case-insensitive)
    static func findCalendar(named name: String) -> EKCalendar? {
        let calendars = eventStore.calendars(for: .event)
        return calendars.first { $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    /// Get all available calendars
    static func allCalendars() -> [EKCalendar] {
        eventStore.calendars(for: .event)
    }

    /// Fetch events from specified calendars within date range
    static func fetchEvents(from calendars: [EKCalendar], start: Date, end: Date) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: calendars
        )
        return eventStore.events(matching: predicate)
    }

    /// Format an event for output
    ///
    /// Output format:
    /// ```
    /// i YYYY-MM-DD HH:MM:SS title    notes
    /// ; :CalendarName:
    /// o YYYY-MM-DD HH:MM:SS
    /// ```
    ///
    /// - Parameters:
    ///   - event: The calendar event to format
    ///   - config: Config containing title mappings
    ///   - includeCalendar: If true, add calendar name as "; :Name:" line
    ///   - includeNotes: If true, append notes to title line (4-space separated)
    ///   - skipMapping: If true, use raw event title without applying mappings
    static func formatEvent(_ event: EKEvent, config: Config, includeCalendar: Bool = false, includeNotes: Bool = false, skipMapping: Bool = false) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let start = dateFormatter.string(from: event.startDate)
        let end = dateFormatter.string(from: event.endDate)

        // Apply title mapping unless skipped
        let rawTitle = event.title ?? "Untitled"
        let title = skipMapping ? rawTitle : config.mapTitle(rawTitle)

        // Build the "i" (in) line with timestamp and title
        var iLine = "i \(start) \(title)"

        // Append notes to the same line if requested (4-space separator)
        if includeNotes, let eventNotes = event.notes, !eventNotes.isEmpty {
            // Collapse multi-line notes to single line
            let singleLineNotes = eventNotes
                .components(separatedBy: .newlines)
                .joined(separator: " ")
            iLine += "    \(singleLineNotes)"
        }

        var lines = [iLine]

        // Add calendar tag line if requested
        if includeCalendar {
            let calendarName = event.calendar?.title ?? "Unknown"
            lines.append("; :\(calendarName):")
        }

        // Add the "o" (out) line with end timestamp
        lines.append("o \(end)")

        return lines.joined(separator: "\n")
    }
}
