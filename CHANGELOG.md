# Changelog

## Unreleased

### Add T&C support

- New params in GlobalSettings: `tc_version: u16` and `accepted_tc: Table<address, u16>` of the latest accepted T&C version per user.
- Admin function: `update_tc(global_settings, version)`: bump tc_version in the global settings, asserts that `version == global_settings.tc_version + 1`.
- New user function: `accept_tc(global_settings, version)`: certifies that the user accepted the latest version and adds the record to `accepted_tc`.
- User can only invest if he accepted the latest T&C.
- `invest` function now takes the Global Settings as a required argument (in the second place).

## v0.2.0 (2025-12-12)

### Features

- Added `create_pod` and `business_plan` as required arguments to `create_pod`.
- PodInfo helper object to store non operational attributes of a Pod and `get_pod_info` function to access it.

### Breaking Changes

- `create_pod`
  - New required arguments: `pitch_deck` and `business_plan`.
  - `forum_url`, `pitch_deck` and `business_plan`. Must be an URL, min len: 9, max len: 42.
  - check `name` argument must have at least 4 characters and max 32 characters.
  - check `description` argument must have max 64 characters.
- Removed `name` and `description` from Pod fields - the are now in PodInfo.

## v0.1.0 (2025-11-25)

Initial release
