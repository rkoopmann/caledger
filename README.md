# caledger

A macOS CLI tool for reading calendar entries and outputting them in a ledger-compatible format.

## Installation

Build the project in Xcode, then copy the executable to your PATH:

```bash
cp ~/Library/Developer/Xcode/DerivedData/caledger-*/Build/Products/Debug/caledger /usr/local/bin/
```

On first run, macOS will prompt for calendar access. Grant permission in System Settings > Privacy & Security > Calendars.

## Usage

```bash
caledger ls [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `-c, --calendar <name>` | Calendar name(s) to read from (repeatable, default: all calendars) |
| `-s, --start <date>` | Start date (YYYY-MM-DD or relative) |
| `-e, --end <date>` | End date (YYYY-MM-DD or relative) |
| `-f, --filter <text>` | Filter events by title (case-insensitive) |
| `-t, --tag` | Tag output with calendar name |
| `-n, --notes` | Include event notes appended to title |
| `-b, --break` | Add date headers between days |
| `--nomap` | Skip title mappings from config |
| `--config-back` | Merge all configs, distant/parent wins conflicts |
| `--config-forward` | Merge all configs, closer/local wins conflicts |
| `-h, --help` | Show help |

### Relative Dates & Times

Dates/times can be absolute (`YYYY-MM-DD` or `YYYY-MM-DD HH:MM`) or relative using these units:

| Unit | Meaning | Type |
|------|---------|------|
| `Y` | year | date |
| `Q` | quarter (3 months) | date |
| `M` | month | date |
| `W` | week | date |
| `D` | day | date |
| `h` | hour | time |
| `m` | minute | time |

Examples: `-1Y`, `+3M`, `-2W4D`, `+1h30m`, `-10m`

### Output Format

```
### 2026-01-06 Monday ###
i 2026-01-06 10:00:00 title    notes
; :CalendarName:
o 2026-01-06 11:00:00
```

- `### YYYY-MM-DD Day ###` header: date separator (if `-b`)
- `i` line: event start time and title (with notes if `-n`)
- `; :CalendarName:` line: calendar tag (if `-t`)
- `o` line: event end time

## Creating Events

Create calendar events with the `mk` command:

```bash
caledger mk -c <calendar> -t <title> [-s <start>] [-e <end>] [-n <notes>]
```

| Option | Description |
|--------|-------------|
| `-c, --calendar` | Calendar to add event to (required) |
| `-t, --title` | Event title (required) |
| `-s, --start` | Start time (default: now) |
| `-e, --end` | End time (default: +1h from start) |
| `-n, --notes` | Event notes |
| `--nomap` | Don't expand title using mappings |

Examples:

```bash
# Create event starting now, ending in 1 hour
caledger mk -c Work -t "Quick meeting"

# Create event with specific times
caledger mk -c Work -t "Lunch" -s "2026-01-07 12:00" -e "2026-01-07 13:00"

# Create event using relative times
caledger mk -c tracked -t "Just did this" -s "-10m" -e "+0m"

# Create event with notes
caledger mk -c Personal -t "Call mom" -s "+1h" -n "Remember to ask about weekend"
```

## Mapping Commands

Manage title mappings that replace event titles in output:

```bash
caledger map ls              # list all mappings
caledger map ls -f <text>    # filter mappings
caledger map add <key> <val> # add or update mapping
caledger map rm <key>        # remove mapping
```

## Configuration File

Caledger looks for a `.caledger` file by traversing up from the current directory. If none is found, it falls back to `~/.caledger`. This allows project-specific configurations.

By default, only the closest config file is loaded. Use `--config-back` or `--config-forward` to merge multiple config files:

- **Default**: Load closest `.caledger` only
- **`--config-back`**: Merge all configs; distant/parent settings win conflicts
- **`--config-forward`**: Merge all configs; closer/local settings win conflicts

Create `.caledger` in your project or home directory:

```
; Settings
calendar = Work, Personal
start = -1m
end = +0d
filter = wb

; Boolean flags
notes
notag
nomap

; Title mappings (event title = replacement)
wb12345 = expenses:travel:client
proj-abc = income:consulting:acme
```

### Config Options

| Key | Description |
|-----|-------------|
| `calendar` | Default calendar(s), comma-separated |
| `start` | Default start date |
| `end` | Default end date |
| `filter` | Default title filter |
| `notes` / `nonotes` | Enable/disable notes |
| `tag` / `notag` | Enable/disable calendar tags |
| `break` / `nobreak` | Enable/disable date headers |
| `map` / `nomap` | Enable/disable title mappings |

Any unrecognized key is treated as a title mapping.

Command line options override config file values.

## Examples

```bash
# List all events from last month
caledger ls -s -1m -e +0d

# List events from specific calendars with tags
caledger ls -c Work -c Personal -t

# Filter events and include notes
caledger ls -f "meeting" -n

# Use relative dates
caledger ls -s -1q -e +1w
```
