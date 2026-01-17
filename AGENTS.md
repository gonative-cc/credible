# AI Agents Instructions

This file provides guidance to AI agents, when working with code in this repository

## Project Summary

Beelievers Kickstarter is a decentralized crowdfunding and incubation platform with a token distribution mechanism, built on Sui blockchain. It's designed to launch and accelerate the next generation of innovative projects from _DeFi and beyond_.

**Stack:** Sui blockchain, Sui Move programming language
**Project specification:** @README.md

### Information about Sui and Sui Move

- Learn about Sui Move: https://move-book.com/reference
- Testing in Sui Move: https://intro.sui-book.com/unit-three/lessons/7_unit_testing.html
- Integrating with Sui through CLI: https://docs.sui.io/references/cli/cheatsheet
- Integration and Scripting with Typescrip: https://sdk.mystenlabs.com/typescript

## Repository Structure

This is a Sui Move project

```
├── Makefile
├── Move.lock
├── Move.toml     # project config file
├── sources
│   └── pod.move  # main module implementation
├── README.md     # project specification
└── tests
    └── pod_tests.move  # comprehensive test suite
```

Files in the `private` directory should be ignored.

## Code Architecture

### Core Module: `beelievers_kickstarter::pod`

The entire platform is implemented in a single Move modules (.move files): production code in `sources` directory and tests in the `tests` directory.

**Key Structs:**

1. **`GlobalSettings`** (shared object): Platform-wide configuration, see "System Parameters" section in @README.md for details.
   These can be updated by `PlatformAdminCap` holder via `update_settings()`.

2. **`Pod<C, T>`** (shared object): Generic crowdfunding campaign
   - Type parameters: `C` = currency type (the one investors use when investing), `T` = token type
   - Contains token vault, funds vault, investment tracking table
   - Manages subscription phase, vesting, and distribution
   - Key fields: `min_goal`, `max_goal`, `vesting_duration`, `immediate_unlock_pm`

3. **`InvestorRecord`** (store in Table): Tracks per-investor state
   - `invested`: Total amount invested
   - `allocation`: Total token allocation
   - `claimed_tokens`: Tokens already claimed
   - `cancelled`: Whether subscription was cancelled

4. **`PodAdminCap`**: Capability to manage a specific pod (issued to founders)
5. **`PlatformAdminCap`**: Capability to update global settings (issued on init)

**Pod Lifecycle:**

1. **INACTIVE**: Before subscription starts
2. **SUBSCRIPTION**: Active investment period (must be ≥ 7 days)
3. **FAILED**: Min goal not reached, refunds issued
4. **GRACE**: Min goal reached, grace period during which vesting doesn't happen, but investors can withdraw with a reduced grace fee.
5. **VESTING**: Success case, funds and tokens vest linearly

**Core Functions:**

- **Pod Creation**: `create_pod()` - Founders supply tokens equal to `max_goal / token_price`
- **Investment**: `invest()` - During subscription, investors contribute funds, receive token allocation
- **Cancellation**: `cancel_subscription()` - Investors can cancel once (`cancel_subscription_keep` is kept).
- **Token Claims**: `investor_claim_tokens()` - Investors claim vested tokens
- **Fund Claims**: `founder_claim_founds()` - Founders claim vested funds
- **Exit Mechanism**: `exit_investment()` - See "Exit Mechanism" section in @README.md.
- **Failed Pod Handling**: `failed_pod_refund()` and `failed_pod_withdraw()`

**Key Design Patterns:**

- **Precise Calculations**: Uses `ratio_ext()` with u128 for overflow-safe arithmetic
- **Events**: Comprehensive event emission for all state changes
- **Generic Types**: `Pod<C, T>` allows any currency/token pair
- **Capability-Based Security**: Admin caps control privileged operations
- **Time-Based State**: Uses `Clock` for timestamp-based logic

## Development Commands

```sh
# Build the project
make build

# Run all tests
make test

# Run tests with coverage
make test-coverage

# Lint the code
make lint

# Format Move files
make format-move

# Format all files (Move + other)
make format-all

# Generate documentation
make gen-docs

# Setup git hooks for formatting
make setup-hooks
```

**Test Structure:**

The test suite (`tests/pod_tests.move`) provides comprehensive coverage:

- Platform initialization and settings updates
- Pod creation validation (all error cases)
- Investment scenarios (single/multiple investors, max goal, cancellations)
- Vesting and claiming logic
- Exit mechanisms (small fee period vs standard fee)
- Failed pod handling
- Edge cases and boundary conditions
- Full integration tests covering complete pod lifecycles

Tests use Sui's `test_scenario` framework with helpers:

- `DAY`, `HOUR`, `MINUTE` constants
- `assert_u64_eq()` and `assert_u8_eq()` assertion helpers
- Common pattern: setup → create pod → invest → verify state transitions

## Key Implementation Details

**Vesting Calculation:** See "Phase 4: Vesting and Token Distribution" section in @README.md.

**Exit Fee Logic:** See "Exit Mechanism" section in @README.md.

**Precision:** All percentage calculations use permille (1000) with u128 intermediate results to prevent overflow.

**Error Codes:** Defined as constants (e.g., `E_INVALID_PARAMS`, `E_POD_NOT_SUBSCRIPTION`) for explicit abort conditions.
