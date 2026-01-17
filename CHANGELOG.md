# Changelog

## Unreleased

### Add T&C support

- New object: `UserStore` with `tc_version: u16` and `accepted_tc: Table<address, u16>` of the latest accepted T&C version per user.
- Admin function: `pod::update_tc(user_store, version)`: bump tc_version, asserts that `version == user_store.tc_version + 1`.
- New user function: `pod::accept_tc(user_store, version)`: certifies that the user accepted the latest version and adds the record to `accepted_tc`.
- New user function: `pod::accepted_tc_version(user_store, user_address): Option(u16)`: return None if the user didn't accept T&C or `Some(version)` of the latest s/he accepted.
- A user can only invest if s/he accepted the latest T&C.
- `invest` function now takes the `UserStore` as a required argument (in the second place).

### Other breaking changes:

- removed `pod::get_grace_fee_pm`
- renamed: `pod::get_global_settings` to `unpack_global_settings`
- renamed: removed _get__ prefix from `pod::get_pod_params`, `pod::get_pod_info`, `pod::pod_num_investors`

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
