module beelievers_kickstarter::settings_tests;

use beelievers_kickstarter::pod::{Self, GlobalSettings, UserStore, PlatformAdminCap};
use sui::test_scenario::{Self, Scenario, next_tx, ctx};

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

fun init1(): (address, Scenario, GlobalSettings, UserStore) {
    let owner = @0x1;
    let mut scenario = test_scenario::begin(owner);

    pod::init_for_tests(scenario.ctx());
    scenario.next_tx(owner);
    let settings = scenario.take_shared<GlobalSettings>();
    let user_store = scenario.take_shared<UserStore>();

    (owner, scenario, settings, user_store)
}

fun cleanup(
    cap: PlatformAdminCap,
    settings: GlobalSettings,
    user_store: UserStore,
    scenario: Scenario,
) {
    scenario.return_to_sender(cap);
    test_scenario::return_shared(settings);
    test_scenario::return_shared(user_store);
    scenario.end();
}

#[test]
fun test_platform_initialization() {
    let (_owner, scenario, settings, user_store) = init1();

    // Verify GlobalSettings was created with correct defaults
    let (
        max_immediate_unlock_pm,
        min_vesting_duration,
        max_vesting_duration,
        min_subscription_duration,
        max_subscription_duration,
        grace_fee_pm,
        grace_duration,
        cancel_subscription_keep,
        setup_fee,
        treasury,
        min_cliff_duration,
        max_cliff_duration,
    ) = pod::get_global_settings(&settings);

    assert_u64_eq(max_immediate_unlock_pm, 100); // 10.0%
    assert_u64_eq(min_vesting_duration, DAY * 30 * 3); // 3 months
    assert_u64_eq(max_vesting_duration, DAY * 30 * 24); // 24 months
    assert_u64_eq(min_subscription_duration, DAY * 7); // 7 days
    assert_u64_eq(max_subscription_duration, DAY * 30); // 30 days
    assert_u64_eq(grace_fee_pm, 8); // 0.8%
    assert_u64_eq(grace_duration, DAY * 3); // 3 days
    assert_u64_eq(cancel_subscription_keep, 1); // 0.1%
    assert_u64_eq(setup_fee, 5_000_000_000); // 5 SUI
    assert!(treasury == @0x1); // owner
    assert_u64_eq(min_cliff_duration, 0);
    assert_u64_eq(max_cliff_duration, DAY * 365 * 2);

    // Verify UserStore was created with correct defaults
    let tc_version = user_store.tc_version();
    assert!(tc_version == 1);

    // Verify PlatformAdminCap was created
    let admin_cap = scenario.take_from_sender<PlatformAdminCap>();

    cleanup(admin_cap, settings, user_store, scenario);
}

// ================================
// Settings Update Tests
// ================================

#[test]
fun test_update_all_settings() {
    let (_owner, mut scenario, mut settings, user_store) = init1();
    let cap = scenario.take_from_sender<PlatformAdminCap>();

    settings.update_settings(
        &cap,
        option::some(100), // 10%
        option::some(DAY * 60), // 2 months min
        option::some(DAY * 365 * 2), // 2 years max
        option::some(DAY * 14), // 14 days min sub
        option::some(DAY * 60), // 60 days max sub
        option::some(10), // 1% grace
        option::some(DAY * 30), // 30 days grace
        option::some(2), // 0.2% keep
        option::some(6_000_000_000), // 6 SUI
        option::some(@0x2), // new treasury
        option::some(DAY * 30), // min cliff
        option::some(DAY * 365 * 3), // max cliff
        ctx(&mut scenario),
    );

    // Verify updates
    let (
        max_immediate_unlock_pm,
        min_vesting_duration,
        max_vesting_duration,
        min_subscription_duration,
        max_subscription_duration,
        grace_fee_pm,
        grace_duration,
        cancel_subscription_keep,
        setup_fee,
        treasury,
        min_cliff_duration,
        max_cliff_duration,
    ) = pod::get_global_settings(&settings);
    assert_u64_eq(max_immediate_unlock_pm, 100);
    assert_u64_eq(min_vesting_duration, DAY * 60);
    assert_u64_eq(max_vesting_duration, DAY * 365 * 2);
    assert_u64_eq(min_subscription_duration, DAY * 14);
    assert_u64_eq(max_subscription_duration, DAY * 60);
    assert_u64_eq(grace_fee_pm, 10);
    assert_u64_eq(grace_duration, DAY * 30);
    assert_u64_eq(cancel_subscription_keep, 2);
    assert_u64_eq(setup_fee, 6_000_000_000);
    assert!(treasury == @0x2);
    assert_u64_eq(min_cliff_duration, DAY * 30);
    assert_u64_eq(max_cliff_duration, DAY * 365 * 3);

    cleanup(cap, settings, user_store, scenario);
}

#[test]
fun test_update_individual_settings() {
    let (_owner, mut scenario, mut settings, user_store) = init1();
    let cap = scenario.take_from_sender<PlatformAdminCap>();

    // Update only one setting
    settings.update_settings(
        &cap,
        option::some(120),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
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
    let (max_immediate_unlock_pm, _, _, _, _, _, _, _, _, _, _, _) = pod::get_global_settings(
        &settings,
    );
    assert_u64_eq(max_immediate_unlock_pm, 120);

    cleanup(cap, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_PARAMS)]
fun test_update_settings_zero_vesting_duration() {
    let (_owner, mut scenario, mut settings, user_store) = init1();
    let cap = scenario.take_from_sender<PlatformAdminCap>();

    // Try to set vesting duration to 0 (should fail)
    settings.update_settings(
        &cap,
        option::none(),
        option::some(0),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        ctx(&mut scenario),
    );

    cleanup(cap, settings, user_store, scenario);
}

#[test]
fun test_settings_update_tc() {
    let (_owner, scenario, settings, mut user_store) = init1();
    let cap = scenario.take_from_sender<PlatformAdminCap>();
    user_store.update_tc(&cap, 2);
    let tc = user_store.tc_version();
    assert!(tc == 2);
    cleanup(cap, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_TC_VERSION)]
fun test_settings_update_tc_not_increment() {
    let (_owner, scenario, settings, mut user_store) = init1();
    let cap = scenario.take_from_sender<PlatformAdminCap>();
    user_store.update_tc(&cap, 3);
    cleanup(cap, settings, user_store, scenario);
}
