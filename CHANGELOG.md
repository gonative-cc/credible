# Changelog

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

