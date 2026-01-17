module beelievers_kickstarter::user_store_tests;

use beelievers_kickstarter::pod::{Self, UserStore, PlatformAdminCap};
use sui::test_scenario::{Self, Scenario, next_tx, ctx};

fun init1(): (address, Scenario, UserStore) {
    let owner = @0x1;
    let mut scenario = test_scenario::begin(owner);

    pod::init_for_tests(scenario.ctx());
    scenario.next_tx(owner);
    let user_store = scenario.take_shared<UserStore>();

    (owner, scenario, user_store)
}

fun cleanup(cap: PlatformAdminCap, user_store: UserStore, scenario: Scenario) {
    scenario.return_to_sender(cap);
    test_scenario::return_shared(user_store);
    scenario.end();
}

#[test]
fun test_user_store_update_tc() {
    let (_owner, scenario, mut user_store) = init1();

    // Verify UserStore was created with correct defaults
    let tc_version = user_store.tc_version();
    assert!(tc_version == 1);

    let cap = scenario.take_from_sender<PlatformAdminCap>();
    user_store.update_tc(&cap, 2);
    let tc = user_store.tc_version();
    assert!(tc == 2);
    cleanup(cap, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_TC_VERSION)]
fun test_user_store_update_tc_not_increment() {
    let (_owner, scenario, mut user_store) = init1();
    let cap = scenario.take_from_sender<PlatformAdminCap>();
    user_store.update_tc(&cap, 3);
    cleanup(cap, user_store, scenario);
}
