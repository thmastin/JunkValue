# Changelog

All notable changes to JunkValue are documented here.

## [1.2.0] - 2026-11-10

### Added
- Add user-defined Always/Never junk lists, slash commands, and Alt+right-click toggling in Blizzard and EllesmereUI bags.
- Add the native options panel, available by right-clicking the bar or using `/junkvalue`.
- Add an icon picker with the white glyph, pouch, and coin, plus the Show icon toggle.

### Fixed
- Migrate existing users' settings and parse item links without changing their case.
- Remove the StaticPopup clear confirmation to prevent popup system taint.

## [1.1.1] - 2026-11-10

### Changed
- Display top junk stacks in two columns, remove the equals separator, and hide `x1` for single items.
- Add the README versioning policy and this changelog.

## [1.1.0] - 2026-11-10

### Added
- Show the top five junk stacks, session vendor earnings, and configurable options.

### Fixed
- Fix the tooltip showing `0c` by reading the same scan snapshot as the bar.

## [1.0.0] - 2026-11-10

### Added
- Initial release: a LibDataBroker data source showing total gray vendor value for the WoW Forever client.
