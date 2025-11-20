module beelievers_kickstarter::settings_tests;

use beelievers_kickstarter::pod::{Self, GlobalSettings, PlatformAdminCap};
use sui::test_scenario::{Self, next_tx, ctx};

const DAY: u64 = HOUR * 24;
const HOUR: u64 = MINUTE * 60;
const MINUTE: u64 = 1000 * 60;

// Helper functions for assertions
fun assert_u64_eq(a: u64, b: u64) {
    assert!(a == b, 0);
}

// ================================
// Platform Initialization Tests
// ================================

#[test]
fun test_platform_initialization() {
    let owner = @0x1;
    let mut scenario = test_scenario::begin(owner);
    let ctx = ctx(&mut scenario);

    // Initialize module
    pod::init_for_tests(ctx);
    next_tx(&mut scenario, owner);

    // Verify GlobalSettings was created with correct defaults
    let settings = scenario.take_shared<GlobalSettings>();
    let (
        max_immediate_unlock_pm,
        min_vesting_duration,
        min_subscription_duration,
        grace_fee_pm,
        small_fee_duration,
        cancel_subscription_keep,
        setup_fee,
        treasury,
    ) = pod::get_global_settings(&settings);

    assert_u64_eq(max_immediate_unlock_pm, 100); // 10.0%
    assert_u64_eq(min_vesting_duration, DAY * 30 * 3); // 3 months
    assert_u64_eq(min_subscription_duration, DAY * 7); // 7 days
    assert_u64_eq(grace_fee_pm, 8); // 0.8%
    assert_u64_eq(small_fee_duration, DAY * 3); // 3 days
    assert_u64_eq(cancel_subscription_keep, 1); // 0.1%
    assert_u64_eq(setup_fee, 5_000_000_000); // 5 SUI
    assert!(treasury == @0x1); // owner
    test_scenario::return_shared(settings);

    // Verify PlatformAdminCap was created
    let admin_cap = scenario.take_from_sender<PlatformAdminCap>();
    test_scenario::return_to_sender(&scenario, admin_cap);

    test_scenario::end(scenario);
}

// ================================
// Settings Update Tests
// ================================

#[test]
fun test_update_all_settings() {
    let owner = @0x1;
    let mut scenario = test_scenario::begin(owner);
    let ctx = ctx(&mut scenario);

    // Initialize
    pod::init_for_tests(ctx);
    next_tx(&mut scenario, owner);

    let mut settings = scenario.take_shared<GlobalSettings>();
    let cap = scenario.take_from_sender<PlatformAdminCap>();

    // Update all settings
    pod::update_settings(
        &cap,
        &mut settings,
        option::some(100), // 10%
        option::some(DAY * 60), // 2 months
        option::some(DAY * 14), // 14 days
        option::some(10), // 1%
        option::some(DAY * 30), // 30 days
        option::some(2), // 0.2%
        option::some(6_000_000_000), // 6 SUI
        option::some(@0x2), // new treasury
        ctx(&mut scenario),
    );

    // Verify updates
    let (
        max_immediate_unlock_pm,
        min_vesting_duration,
        min_subscription_duration,
        grace_fee_pm,
        small_fee_duration,
        cancel_subscription_keep,
        setup_fee,
        treasury,
    ) = pod::get_global_settings(&settings);

    assert_u64_eq(max_immediate_unlock_pm, 100);
    assert_u64_eq(min_vesting_duration, DAY * 60);
    assert_u64_eq(min_subscription_duration, DAY * 14);
    assert_u64_eq(grace_fee_pm, 10);
    assert_u64_eq(small_fee_duration, DAY * 30);
    assert_u64_eq(cancel_subscription_keep, 2);
    assert_u64_eq(setup_fee, 6_000_000_000);
    assert!(treasury == @0x2);

    test_scenario::return_to_sender(&scenario, cap);
    test_scenario::return_shared(settings);
    test_scenario::end(scenario);
}

#[test]
fun test_update_individual_settings() {
    let owner = @0x1;
    let mut scenario = test_scenario::begin(owner);
    let ctx = ctx(&mut scenario);

    pod::init_for_tests(ctx);
    next_tx(&mut scenario, owner);

    let mut settings = scenario.take_shared<GlobalSettings>();
    let cap = scenario.take_from_sender<PlatformAdminCap>();

    // Update only one setting
    pod::update_settings(
        &cap,
        &mut settings,
        option::some(120),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        ctx(&mut scenario),
    );

    // Verify only max_immediate_unlock changed
    let (max_immediate_unlock_pm, _, _, _, _, _, _, _) = pod::get_global_settings(
        &settings,
    );

    assert_u64_eq(max_immediate_unlock_pm, 120);

    test_scenario::return_to_sender(&scenario, cap);
    test_scenario::return_shared(settings);
    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_PARAMS)]
fun test_update_settings_zero_vesting_duration() {
    let owner = @0x1;
    let mut scenario = test_scenario::begin(owner);
    let ctx = ctx(&mut scenario);

    pod::init_for_tests(ctx);
    next_tx(&mut scenario, owner);

    let mut settings = scenario.take_shared<GlobalSettings>();
    let cap = scenario.take_from_sender<PlatformAdminCap>();

    // Try to set vesting duration to 0 (should fail)
    pod::update_settings(
        &cap,
        &mut settings,
        option::none(),
        option::some(0),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        ctx(&mut scenario),
    );

    test_scenario::return_to_sender(&scenario, cap);
    test_scenario::return_shared(settings);
    test_scenario::end(scenario);
}
