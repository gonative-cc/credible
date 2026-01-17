#[allow(unused_let_mut)]
module beelievers_kickstarter::pod_tests;

use beelievers_kickstarter::pod::{
    Self,
    GlobalSettings,
    UserStore,
    Pod,
    PodAdminCap,
    PlatformAdminCap,
    ratio_ext_pm,
    ratio_ext,
    init_for_tests,
    create_pod,
    accept_tc
};
use sui::clock::Clock;
use sui::coin::mint_for_testing;
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario, next_tx, ctx};

const DAY: u64 = HOUR * 24;
const HOUR: u64 = MINUTE * 60;
const MINUTE: u64 = 1000 * 60;

const PRICE_MULTIPLIER: u64 = 10;
const TOKEN_PRICE: u64 = 1; // effectively this the price is price/multiplier = 0.1
const MIN_GOAL: u64 = 800_000;
const MAX_GOAL: u64 = 1_000_000;
const REQUIRED_TOKENS: u64 = (MAX_GOAL * PRICE_MULTIPLIER) / TOKEN_PRICE;
const IMMEDIATE_UNLOCK_PM: u64 = 50;
const SUBSCRIPTION_START: u64 = MINUTE; // time delta from "now" to subscription start
const TIME_SUBCRIB: u64 = SUBSCRIPTION_START + MINUTE;
const SUBS_DURATION: u64 = DAY * 7; // subscription duration
const VESTING_DURATION: u64 = DAY * 100;
const GRACE_DURATION: u64 = DAY * 3;
const CLIFF_DURATION: u64 = DAY;

// Helper functions for assertions
fun assert_u64_eq(a: u64, b: u64) {
    assert!(a == b, 0);
}

fun assert_u8_eq(a: u8, b: u8) {
    assert!(a == b, 0);
}

/// Helper to accept latest T&C
fun accept_latest_tc(user_store: &mut UserStore, scenario: &mut Scenario) {
    let tc_version = user_store.tc_version();
    user_store.accept_tc(tc_version, scenario.ctx());
}

fun invest1<C, T>(
    pod: &mut Pod<C, T>,
    user_store: &UserStore,
    amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let investment = mint_for_testing(amount, ctx);
    let _excess = pod.invest(user_store, investment, clock, ctx);
    assert_u64_eq(_excess.value(), 0);
    transfer::public_transfer(_excess, @0x0);
}

/// creates Pod<SUI, SUI>
fun init1(owner: address): (Scenario, Clock, GlobalSettings, UserStore) {
    init_t(
        owner,
        REQUIRED_TOKENS,
        TOKEN_PRICE,
        PRICE_MULTIPLIER,
        MIN_GOAL,
        MAX_GOAL,
        SUBS_DURATION,
        VESTING_DURATION,
        IMMEDIATE_UNLOCK_PM,
        0, // cliff_duration
        false, // cliff_token_immediate_unlock
    )
}

/// creates pod, accepts tc and moves to subscription start.
fun init2(time: u64): (Scenario, Clock, GlobalSettings, UserStore, Pod<SUI, SUI>) {
    let founder = @0x1;
    let investor = @0x2;
    let (mut scenario, mut clock, mut settings, mut user_store) = init1(founder);
    scenario.next_tx(investor);
    accept_latest_tc(&mut user_store, &mut scenario);

    clock.increment_for_testing(time);
    let pod = scenario.take_shared<Pod<SUI, SUI>>();

    (scenario, clock, settings, user_store, pod)
}

/// creates Pod<SUI, SUI> with cliff
fun init_cliff(owner: address, cliff_unlock: bool): (Scenario, Clock, GlobalSettings, UserStore) {
    init_t(
        owner,
        REQUIRED_TOKENS,
        TOKEN_PRICE,
        PRICE_MULTIPLIER,
        MIN_GOAL,
        MAX_GOAL,
        SUBS_DURATION,
        VESTING_DURATION,
        IMMEDIATE_UNLOCK_PM,
        CLIFF_DURATION,
        cliff_unlock,
    )
}

/// creates Pod<SUI, SUI>
fun init_t(
    owner: address,
    required_tokens: u64,
    token_price: u64,
    price_multiplier: u64,
    min_goal: u64,
    max_goal: u64,
    subs_dur: u64,
    vesting_dur: u64,
    immediate_unlock_pm: u64,
    cliff_dur: u64,
    cliff_token_immediate_unlock: bool,
): (Scenario, Clock, GlobalSettings, UserStore) {
    let mut scenario = test_scenario::begin(owner);
    let mut clock = sui::clock::create_for_testing(scenario.ctx());

    init_for_tests(scenario.ctx());
    scenario.next_tx(owner);

    let subscription_start = clock.timestamp_ms() + SUBSCRIPTION_START;
    let tokens = mint_for_testing<SUI>(required_tokens, scenario.ctx());
    let mut settings = scenario.take_shared<GlobalSettings>();
    let user_store = scenario.take_shared<UserStore>();
    let setup_fee = mint_for_testing<SUI>(5_000_000_000, scenario.ctx()); // 5 SUI

    create_pod<SUI, SUI>(
        &settings,
        b"My Project".to_string(),
        b"Great project".to_string(),
        b"https://example.com".to_string(),
        b"https://forum.example.com".to_string(),
        b"https://pitch.example.com".to_string(),
        b"https://business.example.com".to_string(),
        token_price,
        price_multiplier,
        min_goal,
        max_goal,
        subscription_start,
        subs_dur,
        vesting_dur,
        immediate_unlock_pm,
        cliff_dur,
        cliff_token_immediate_unlock,
        tokens,
        setup_fee,
        &clock,
        scenario.ctx(),
    );

    (scenario, clock, settings, user_store)
}

fun cleanup1(c: Clock, settings: GlobalSettings, user_store: UserStore, scenario: Scenario) {
    test_scenario::return_shared(settings);
    test_scenario::return_shared(user_store);
    c.destroy_for_testing();
    scenario.end();
}

fun cleanup<C, T>(
    c: Clock,
    pod: Pod<C, T>,
    settings: GlobalSettings,
    user_store: UserStore,
    scenario: Scenario,
) {
    test_scenario::return_shared(pod);
    cleanup1(c, settings, user_store, scenario);
}

// ================================
// Pod Creation Tests
// ================================

#[test]
fun test_create_pod_success() {
    let owner = @0x1;
    let (mut scenario, clock, mut settings, user_store) = init1(owner);

    // Start new transaction to access created pod
    scenario.next_tx(owner);

    // Verify pod exists and has correct parameters
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let cap = scenario.take_from_sender<PodAdminCap>();

    let params = pod.get_pod_params();
    assert_u64_eq(params.get_pod_token_price(), TOKEN_PRICE);
    assert_u64_eq(params.get_pod_price_multiplier(), PRICE_MULTIPLIER);
    assert_u64_eq(params.get_pod_min_goal(), MIN_GOAL);
    assert_u64_eq(params.get_pod_max_goal(), MAX_GOAL);
    assert_u64_eq(params.get_pod_vesting_duration(), VESTING_DURATION);
    assert_u64_eq(params.get_pod_immediate_unlock_pm(), IMMEDIATE_UNLOCK_PM);

    test_scenario::return_to_sender(&scenario, cap);
    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_PARAMS)]
fun test_create_pod_invalid_min_goal() {
    let (mut scenario, c, mut settings, user_store) = init_t(
        @0x1,
        REQUIRED_TOKENS,
        TOKEN_PRICE,
        PRICE_MULTIPLIER,
        0, // min_goal = 0 (should fail)
        MAX_GOAL,
        SUBS_DURATION,
        VESTING_DURATION,
        IMMEDIATE_UNLOCK_PM,
        0,
        false,
    );
    cleanup1(c, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_PARAMS)]
fun test_create_pod_max_less_than_min() {
    let (mut scenario, c, mut settings, user_store) = init_t(
        @0x1,
        REQUIRED_TOKENS,
        TOKEN_PRICE,
        PRICE_MULTIPLIER,
        MAX_GOAL, // reversed arguments
        MIN_GOAL,
        SUBS_DURATION,
        VESTING_DURATION,
        IMMEDIATE_UNLOCK_PM,
        0,
        false,
    );
    cleanup1(c, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_PARAMS)]
fun test_create_pod_subscription_duration_too_short() {
    let (mut scenario, c, mut settings, user_store) = init_t(
        @0x1,
        REQUIRED_TOKENS,
        TOKEN_PRICE,
        PRICE_MULTIPLIER,
        MIN_GOAL,
        MAX_GOAL,
        DAY * 1, // subscription duration
        VESTING_DURATION,
        IMMEDIATE_UNLOCK_PM,
        0,
        false,
    );
    cleanup1(c, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_PARAMS)]
fun test_create_pod_subscription_duration_too_long() {
    let (mut scenario, c, mut settings, user_store) = init_t(
        @0x1,
        REQUIRED_TOKENS,
        TOKEN_PRICE,
        PRICE_MULTIPLIER,
        MIN_GOAL,
        MAX_GOAL,
        DAY * 31, // subscription duration > 30 days
        VESTING_DURATION,
        IMMEDIATE_UNLOCK_PM,
        0,
        false,
    );
    cleanup1(c, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_PARAMS)]
fun test_create_pod_vesting_duration_too_short() {
    let (mut scenario, c, mut settings, user_store) = init_t(
        @0x1,
        REQUIRED_TOKENS,
        TOKEN_PRICE,
        PRICE_MULTIPLIER,
        MIN_GOAL,
        MAX_GOAL,
        SUBS_DURATION,
        DAY * 1, // vesting duration
        IMMEDIATE_UNLOCK_PM,
        0,
        false,
    );
    cleanup1(c, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_PARAMS)]
fun test_create_pod_vesting_duration_too_long() {
    let (mut scenario, c, mut settings, user_store) = init_t(
        @0x1,
        REQUIRED_TOKENS,
        TOKEN_PRICE,
        PRICE_MULTIPLIER,
        MIN_GOAL,
        MAX_GOAL,
        SUBS_DURATION,
        DAY * 30 * 25, // 25 months > 24 months max
        IMMEDIATE_UNLOCK_PM,
        0,
        false,
    );
    cleanup1(c, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_PARAMS)]
fun test_create_pod_immediate_unlock_too_high() {
    let (mut scenario, c, mut settings, user_store) = init_t(
        @0x1,
        REQUIRED_TOKENS,
        TOKEN_PRICE,
        PRICE_MULTIPLIER,
        MIN_GOAL,
        MAX_GOAL,
        SUBS_DURATION,
        VESTING_DURATION,
        110, // 11% > 10% max (should fail)
        0,
        false,
    );
    cleanup1(c, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_TOKEN_SUPPLY)]
fun test_create_pod_wrong_token_supply() {
    let (mut scenario, c, mut settings, user_store) = init_t(
        @0x1,
        REQUIRED_TOKENS / 2, // Provide less tokens (should fail)
        TOKEN_PRICE,
        PRICE_MULTIPLIER,
        MIN_GOAL,
        MAX_GOAL,
        SUBS_DURATION,
        VESTING_DURATION,
        IMMEDIATE_UNLOCK_PM,
        0,
        false,
    );
    cleanup1(c, settings, user_store, scenario);
}

// ================================
// Investment Tests
// ================================

#[test]
fun test_successful_investment() {
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(TIME_SUBCRIB);

    let investment = mint_for_testing(100_000, scenario.ctx());
    let excess = pod.invest(&user_store, investment, &clock, scenario.ctx());

    // Verify no excess returned
    assert_u64_eq(excess.value(), 0);
    transfer::public_transfer(excess, @0x0);

    // Verify investment was recorded
    assert_u64_eq(pod.pod_total_allocated(), (100_000 * PRICE_MULTIPLIER) / TOKEN_PRICE);

    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_POD_NOT_SUBSCRIPTION)]
fun test_invest_before_subscription() {
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(1);
    invest1(&mut pod, &user_store, 100_000, &clock, scenario.ctx());
    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_POD_NOT_SUBSCRIPTION)]
fun test_invest_after_subscription_end() {
    let founder = @0x1;
    let investor = @0x2;
    let (mut scenario, mut clock, mut settings, mut user_store) = init1(founder);

    // Fast forward past subscription end
    scenario.next_tx(founder);
    // Subscription is 7days, starts in 1min, so 8days is enouh
    clock.increment_for_testing(SUBSCRIPTION_START + SUBS_DURATION + DAY);

    // Try to invest after subscription ends (should fail)
    scenario.next_tx(investor);
    accept_latest_tc(&mut user_store, &mut scenario);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment = mint_for_testing<SUI>(100_000, scenario.ctx());
    let _excess = pod.invest(&user_store, investment, &clock, scenario.ctx());
    transfer::public_transfer(_excess, @0x0);

    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_TC_NOT_ACCEPTED)]
fun test_invest_not_accepted_tc() {
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(TIME_SUBCRIB);
    scenario.next_tx(@0x3);
    invest1(&mut pod, &user_store, 100_000, &clock, scenario.ctx());
    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_TC_NOT_ACCEPTED)]
fun test_invest_not_accepted_latest_tc() {
    let founder = @0x1;
    let investor = @0x2;
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(TIME_SUBCRIB);
    scenario.next_tx(founder);
    let cap = scenario.take_from_sender<PlatformAdminCap>();
    user_store.update_tc(&cap, 2);

    scenario.next_tx(investor);
    invest1(&mut pod, &user_store, 100_000, &clock, scenario.ctx());

    test_scenario::return_to_sender(&scenario, cap);
    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
fun test_invest_accepted_latest_tc() {
    let founder = @0x1;
    let investor = @0x2;
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(TIME_SUBCRIB);
    scenario.next_tx(founder);
    let cap = scenario.take_from_sender<PlatformAdminCap>();
    user_store.update_tc(&cap, 2);
    test_scenario::return_to_sender(&scenario, cap);

    scenario.next_tx(investor);
    user_store.accept_tc(2, scenario.ctx());
    invest1(&mut pod, &user_store, 100_000, &clock, scenario.ctx());

    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
fun test_max_goal_reached_early() {
    let investor2 = @0x3;
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(TIME_SUBCRIB);

    let investment1 = mint_for_testing(900_000, scenario.ctx());
    let excess1 = pod.invest(&user_store, investment1, &clock, scenario.ctx());
    assert_u64_eq(excess1.value(), 0);
    transfer::public_transfer(excess1, @0x0);

    // Second investment exceeds max, excess returned
    scenario.next_tx(investor2);
    accept_latest_tc(&mut user_store, &mut scenario);
    let investment2 = mint_for_testing(200_000, scenario.ctx());
    let excess2 = pod.invest(&user_store, investment2, &clock, scenario.ctx());

    // Should have 100_000 excess
    assert_u64_eq(excess2.value(), 100_000);
    let params = pod.get_pod_params();
    assert_u64_eq(pod.get_pod_total_raised(), MAX_GOAL);
    assert_u64_eq(params.get_pod_subscription_end(), clock.timestamp_ms());
    transfer::public_transfer(excess2, @0x0);

    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_POD_NOT_SUBSCRIPTION)]
fun test_invest_after_max_goal() {
    let investor2 = @0x3;
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(TIME_SUBCRIB);

    // First investment reaches max
    invest1(&mut pod, &user_store, 1_000_000, &clock, scenario.ctx());

    // Second investment should fail
    scenario.next_tx(investor2);
    accept_latest_tc(&mut user_store, &mut scenario);
    invest1(&mut pod, &user_store, 100_000, &clock, scenario.ctx());

    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
fun test_multiple_investments_same_investor() {
    let investor = @0x2;
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(TIME_SUBCRIB);

    // First investment
    invest1(&mut pod, &user_store, 100_000, &clock, scenario.ctx());
    // Second investment from same investor
    scenario.next_tx(investor);
    invest1(&mut pod, &user_store, 50_000, &clock, scenario.ctx());

    // Total should be combined
    assert_u64_eq(pod.get_pod_total_raised(), 150_000);

    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
fun test_cancel_subscription() {
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(TIME_SUBCRIB);

    invest1(&mut pod, &user_store, 100_000, &clock, scenario.ctx());

    // Cancel subscription
    let refund = pod.cancel_subscription(
        &settings,
        &clock,
        scenario.ctx(),
    );

    // Should get most of investment back (keep 0.1%)
    let kept = 100_000 / 1000;
    let expected_refund = 100_000 - kept;
    assert_u64_eq(refund.value(), expected_refund);
    transfer::public_transfer(refund, @0x0);

    // Total raised should be reduced
    assert_u64_eq(pod.get_pod_total_raised(), kept);

    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_INVESTMENT_CANCELLED)]
fun test_cancel_subscription_only_once() {
    let investor = @0x2;
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(TIME_SUBCRIB);

    // Investor invests and cancels
    invest1(&mut pod, &user_store, 100_000, &clock, scenario.ctx());
    let refund = pod.cancel_subscription(
        &settings,
        &clock,
        scenario.ctx(),
    );
    transfer::public_transfer(refund, @0x0);

    // Try to cancel again (should fail)
    scenario.next_tx(investor);
    let _refund2 = pod.cancel_subscription(
        &settings,
        &clock,
        scenario.ctx(),
    );
    transfer::public_transfer(_refund2, @0x0);

    cleanup(clock, pod, settings, user_store, scenario);
}

// ================================
// Vesting and Claiming Tests
// ================================

#[test]
fun test_calculate_vested_tokens() {
    let total_allocation = 1_000_000;
    let immediate_unlock_pm = 80; // 8%
    let vesting_duration = DAY * 365; // 1 year

    // At time 0, only immediate unlock is available
    let vested = pod::calculate_vested_tokens(
        0,
        vesting_duration,
        immediate_unlock_pm,
        total_allocation,
    );
    let immediate_unlock = ratio_ext_pm(total_allocation, immediate_unlock_pm);
    assert_u64_eq(vested, immediate_unlock);

    // After 6 months (half vesting), should have 50% of remaining + immediate
    let half_vested = pod::calculate_vested_tokens(
        DAY * 182,
        vesting_duration,
        immediate_unlock_pm,
        total_allocation,
    );
    let expected =
        immediate_unlock + pod::ratio_ext(DAY * 182, total_allocation - immediate_unlock, vesting_duration);
    assert_u64_eq(half_vested, expected);

    // After full vesting period
    let fully_vested = pod::calculate_vested_tokens(
        DAY * 365,
        vesting_duration,
        immediate_unlock_pm,
        total_allocation,
    );
    // After full vesting, all tokens (including immediate unlock) are vested
    assert_u64_eq(fully_vested, total_allocation);
}

#[test]
fun test_investor_claim_tokens() {
    let investor = @0x2;
    // Fast forward to just before subscription ends, then invest
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(SUBS_DURATION);
    invest1(&mut pod, &user_store, 1_000_000, &clock, scenario.ctx());

    // Fast forward past grace to vesting start, then claim
    clock.increment_for_testing(GRACE_DURATION + MINUTE);
    scenario.next_tx(investor);
    // Verify pod is now in vesting
    assert!(pod.pod_status(&clock) == pod::status_vesting());

    // Investor claims tokens
    let claimed_tokens = pod.investor_claim_tokens(&clock, scenario.ctx());
    // Investment: 1_000_000, Token allocation: 1_000_000 * 10 / 1 = 10_000_000 tokens
    // Immediate unlock (5%): 10_000_000 * 50 / 1000 = 500_000 tokens
    // 1min vested tokens: (10_000_000 - 500_000) * minute/vesting_duration
    let expected = 500_000 + (10_000_000 - 500_000) * MINUTE / VESTING_DURATION;

    assert_u64_eq(claimed_tokens.value(), expected);
    transfer::public_transfer(claimed_tokens, @0x0);

    // TODO: add more tests:
    // second claim after 1 day
    // another claim at the end of the vesting

    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
fun test_founder_claim_funds() {
    let founder = @0x1;

    // Fast forward to just before subscription ends and invest
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(SUBS_DURATION);
    invest1(&mut pod, &user_store, 1_000_000, &clock, scenario.ctx());

    // Fast forward past grace period, then claim (time elapsed > 0)
    clock.increment_for_testing(DAY * 3 + MINUTE);
    scenario.next_tx(founder);
    let cap = scenario.take_from_sender<PodAdminCap>();
    let claimed_funds = pod.founder_claim_funds(
        &cap,
        &clock,
        scenario.ctx(),
    );

    // Should receive more than immediate unlock due to 1 minute of vesting
    // Investment: 1_000_000, immediate unlock: 50_000
    // With 1 minute elapsed in 100-day vesting: ~50,006
    let expected = 50_006;
    assert!(claimed_funds.value() == expected, 0);
    transfer::public_transfer(claimed_funds, @0x0);

    test_scenario::return_to_sender(&scenario, cap);
    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
fun test_founder_claim_funds_with_cliff() {
    let founder = @0x1;
    let investor = @0x2;

    let (mut scenario, mut clock, mut settings, mut user_store) = init_cliff(founder, true);

    // Fast forward to just before subscription ends, then invest
    clock.increment_for_testing(DAY * 7);
    scenario.next_tx(investor);
    accept_latest_tc(&mut user_store, &mut scenario);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    invest1(&mut pod, &user_store, 1_000_000, &clock, scenario.ctx());
    test_scenario::return_shared(pod);

    // Fast forward past grace to cliff
    clock.increment_for_testing(GRACE_DURATION + MINUTE);
    scenario.next_tx(founder);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let cap = scenario.take_from_sender<PodAdminCap>();
    // Verify pod is in cliff
    assert!(pod.pod_status(&clock) == pod::status_cliff());

    let claimed_funds = pod.founder_claim_funds(
        &cap,
        &clock,
        scenario.ctx(),
    );

    // Should receive immediate unlock
    // Investment: 1_000_000, immediate unlock: 50_000
    let expected = 50_000;
    assert_u64_eq(claimed_funds.value(), expected);
    transfer::public_transfer(claimed_funds, @0x0);

    test_scenario::return_to_sender(&scenario, cap);
    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_POD_NOT_VESTING)]
fun test_withdraw_unallocated_tokens() {
    let investor = @0x2;

    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(TIME_SUBCRIB);
    invest1(&mut pod, &user_store, MAX_GOAL, &clock, scenario.ctx());

    // Fast forward to grace period
    clock.increment_for_testing(GRACE_DURATION / 2);

    // Try to claim tokens (should fail)
    scenario.next_tx(investor);
    let _claimed = pod.investor_claim_tokens(&clock, scenario.ctx());
    transfer::public_transfer(_claimed, @0x0);

    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = pod::E_POD_NOT_VESTING)]
fun test_grace_period_cannot_claim_funds() {
    let founder = @0x1;
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(TIME_SUBCRIB);

    // move time a bit more and use founder to do self investment
    clock.increment_for_testing(MINUTE * 2);
    scenario.next_tx(founder);
    user_store.accept_tc(1, scenario.ctx());
    invest1(&mut pod, &user_store, 800_000, &clock, scenario.ctx());
    test_scenario::return_shared(pod);

    // Fast forward to grace period
    clock.increment_for_testing(GRACE_DURATION / 2);

    // Try to claim funds (should fail)
    scenario.next_tx(founder);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let cap = scenario.take_from_sender<PodAdminCap>();
    let _claimed = pod.founder_claim_funds(&cap, &clock, scenario.ctx());
    transfer::public_transfer(_claimed, @0x0);

    test_scenario::return_to_sender(&scenario, cap);
    cleanup(clock, pod, settings, user_store, scenario);
}

// ================================
// Exit Mechanism Tests
// ================================

/// Helper to setup pod for exit tests
fun helper_test_exit(is_grace: bool): (Scenario, Clock, GlobalSettings, UserStore, Pod<SUI, SUI>) {
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(TIME_SUBCRIB);
    invest1(&mut pod, &user_store, MAX_GOAL, &clock, scenario.ctx());

    // Fast forward to grace or after
    if (is_grace) {
        clock.increment_for_testing(GRACE_DURATION / 2);
    } else {
        clock.increment_for_testing(GRACE_DURATION + DAY);
    };

    (scenario, clock, settings, user_store, pod)
}

#[test]
fun test_exit_grace_period() {
    // TODO: add scenario with more than one investor
    // scenario1: single investor taking max goal

    let (mut scenario, clock, s, user_store, mut pod) = helper_test_exit(true);

    // Investor exits during grace
    scenario.next_tx(@0x2);
    assert!(pod.pod_status(&clock) == pod::status_grace());
    let (refund, vested_tokens) = pod.exit_investment(&clock, scenario.ctx());

    let fee = s.get_grace_fee_pm();
    let expected_refund = 1_000_000 - ratio_ext_pm(1_000_000, fee);
    assert_u64_eq(refund.value(), expected_refund);
    assert_u64_eq(vested_tokens.value(), ratio_ext_pm(REQUIRED_TOKENS, fee));
    assert!(pod.pod_status(&clock) == pod::status_grace());
    transfer::public_transfer(refund, @0x0);
    transfer::public_transfer(vested_tokens, @0x0);

    cleanup(clock, pod, s, user_store, scenario);
}

#[test]
fun test_exit_after_grace_period() {
    let (mut scenario, clock, settings, user_store, mut pod) = helper_test_exit(false);

    // Investor exits after grace fee period
    scenario.next_tx(@0x2);
    let (refund, vested_tokens) = pod.exit_investment(
        &clock,
        scenario.ctx(),
    );

    // Should get refund with standard 10% fee
    assert!(refund.value() > 0);
    assert!(pod.pod_status(&clock) == pod::status_vesting());
    transfer::public_transfer(refund, @0x0);
    transfer::public_transfer(vested_tokens, @0x0);

    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = 1, location = sui::dynamic_field)]
fun test_exit_grace_period_only_once() {
    let (mut scenario, clock, s, user_store, mut pod) = helper_test_exit(true);

    // First exit
    scenario.next_tx(@0x2);
    let (_refund, _vested) = pod.exit_investment(&clock, scenario.ctx());
    transfer::public_transfer(_refund, @0x0);
    transfer::public_transfer(_vested, @0x0);
    test_scenario::return_shared(pod);

    // Try to exit again (should fail)
    scenario.next_tx(@0x2);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let (_refund2, _vested2) = pod.exit_investment(&clock, scenario.ctx());
    transfer::public_transfer(_refund2, @0x0);
    transfer::public_transfer(_vested2, @0x0);

    cleanup(clock, pod, s, user_store, scenario);
}

#[test]
#[expected_failure(abort_code = 1, location = sui::dynamic_field)]
fun test_exit_after_grace_period_only_once() {
    let (mut scenario, clock, settings, user_store, mut pod) = helper_test_exit(false);

    // First exit
    scenario.next_tx(@0x2);
    let (_refund, _vested) = pod.exit_investment(&clock, scenario.ctx());
    transfer::public_transfer(_refund, @0x0);
    transfer::public_transfer(_vested, @0x0);
    test_scenario::return_shared(pod);

    // Try to exit again (should fail)
    scenario.next_tx(@0x2);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let (_refund2, _vested2) = pod.exit_investment(&clock, scenario.ctx());
    transfer::public_transfer(_refund2, @0x0);
    transfer::public_transfer(_vested2, @0x0);

    cleanup(clock, pod, settings, user_store, scenario);
}

// ================================
// Failed Pod Tests
// ================================

#[test]
fun test_failed_pod_refund() {
    let investor = @0x2;
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(TIME_SUBCRIB);
    invest1(&mut pod, &user_store, 500_000, &clock, scenario.ctx());

    // Fast forward past subscription end
    clock.increment_for_testing(SUBS_DURATION + HOUR);

    // Investor gets full refund
    scenario.next_tx(investor);
    let refund = pod.failed_pod_refund(&clock, scenario.ctx());
    assert_u64_eq(refund.value(), 500_000);
    transfer::public_transfer(refund, @0x0);

    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
fun test_failed_pod_withdraw_tokens() {
    let founder = @0x1;
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(TIME_SUBCRIB);
    invest1(&mut pod, &user_store, 500_000, &clock, scenario.ctx());

    // Fast forward to failure
    clock.increment_for_testing(DAY * 7 + HOUR);

    // Founder withdraws all tokens
    scenario.next_tx(founder);
    let cap = scenario.take_from_sender<PodAdminCap>();
    let withdrawn = pod.failed_pod_withdraw(&cap, &clock, scenario.ctx());
    assert_u64_eq(withdrawn.value(), (MAX_GOAL * PRICE_MULTIPLIER) / TOKEN_PRICE);
    transfer::public_transfer(withdrawn, @0x0);

    test_scenario::return_to_sender(&scenario, cap);
    cleanup(clock, pod, settings, user_store, scenario);
}

// ================================
// Edge Cases and Boundary Tests
// ================================

#[test]
#[expected_failure(abort_code = pod::E_ZERO_INVESTMENT)]
fun test_zero_investment() {
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(TIME_SUBCRIB);
    invest1(&mut pod, &user_store, 0, &clock, scenario.ctx());

    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
fun test_pod_status_transitions() {
    let founder = @0x1;

    let (mut scenario, mut clock, mut settings, user_store) = init1(founder);

    // Start new transaction to access created pod
    scenario.next_tx(founder);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();

    // Before subscription starts
    assert_u8_eq(pod.pod_status(&clock), 0);
    test_scenario::return_shared(pod);

    // During subscription
    clock.increment_for_testing(HOUR * 2);
    scenario.next_tx(founder);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    assert_u8_eq(pod.pod_status(&clock), 1);
    test_scenario::return_shared(pod);

    // After subscription ends, min goal not reached
    clock.increment_for_testing(DAY * 7);
    scenario.next_tx(founder);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    assert_u8_eq(pod.pod_status(&clock), 2);

    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
fun test_grace_and_vesting_status() {
    let founder = @0x1;
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(TIME_SUBCRIB);
    invest1(&mut pod, &user_store, 800_000, &clock, scenario.ctx());

    // Fast forward to grace period
    clock.increment_for_testing(DAY * 7);
    scenario.next_tx(founder);
    assert_u8_eq(pod.pod_status(&clock), 3); // GRACE
    test_scenario::return_shared(pod);

    // Fast forward past grace to vesting
    clock.increment_for_testing(DAY * 3);
    scenario.next_tx(founder);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    assert_u8_eq(pod.pod_status(&clock), 5); // VESTING

    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
fun test_ratio_ext_precision() {
    // Test that ratio_ext handles large numbers correctly
    let result1 = ratio_ext(1_000_000, 1_000_000, 3);
    // 1_000_000 * 1_000_000 / 3 = 333_333_333_333.33... -> 333_333_333_333
    assert_u64_eq(result1, 333_333_333_333);

    let result2 = ratio_ext_pm(1_000_000, 80);
    // 1_000_000 * 80 / 1000 = 80_000
    assert_u64_eq(result2, 80_000);
}

// ================================
// Integration Tests
// ================================

#[test]
fun test_full_pod_lifecycle_success() {
    let founder = @0x1;
    let investor1 = @0x2;
    let investor2 = @0x3;
    let investor3 = @0x4;

    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(TIME_SUBCRIB);
    invest1(&mut pod, &user_store, 300_000, &clock, scenario.ctx());

    scenario.next_tx(investor2);
    accept_latest_tc(&mut user_store, &mut scenario);
    invest1(&mut pod, &user_store, 250_000, &clock, scenario.ctx());

    scenario.next_tx(investor3);
    accept_latest_tc(&mut user_store, &mut scenario);

    let inv3_investment = mint_for_testing(500_000, scenario.ctx());
    let excess3 = pod.invest(&user_store, inv3_investment, &clock, scenario.ctx());
    assert_u64_eq(excess3.value(), 50_000);
    transfer::public_transfer(excess3, @0x0);
    test_scenario::return_shared(pod);

    // 5. Fast forward to vesting
    clock.increment_for_testing(DAY * 7);

    // 6. Investors claim immediate unlock
    scenario.next_tx(investor1);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let claimed1 = pod.investor_claim_tokens(&clock, scenario.ctx());
    assert!(claimed1.value() > 0);
    transfer::public_transfer(claimed1, @0x0);
    test_scenario::return_shared(pod);

    scenario.next_tx(investor2);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let claimed2 = pod.investor_claim_tokens(&clock, scenario.ctx());
    assert!(claimed2.value() > 0);
    transfer::public_transfer(claimed2, @0x0);
    test_scenario::return_shared(pod);

    // 7. Founder claims funds
    scenario.next_tx(founder);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let cap = scenario.take_from_sender<PodAdminCap>();
    let founder_claimed = pod.founder_claim_funds(
        &cap,
        &clock,
        scenario.ctx(),
    );
    assert!(founder_claimed.value() > 0);
    transfer::public_transfer(founder_claimed, @0x0);
    test_scenario::return_to_sender(&scenario, cap);
    test_scenario::return_shared(pod);

    // 8. Halfway through vesting, investor 1 exits
    clock.increment_for_testing(DAY * 50);

    scenario.next_tx(investor1);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let (refund, vested_tokens) = pod.exit_investment(
        &clock,
        scenario.ctx(),
    );
    assert!(refund.value() > 0);
    assert!(vested_tokens.value() > 0);
    transfer::public_transfer(refund, @0x0);
    transfer::public_transfer(vested_tokens, @0x0);

    cleanup(clock, pod, settings, user_store, scenario);
}

#[test]
fun test_full_pod_lifecycle_failure() {
    let founder = @0x1;
    let investor = @0x2;

    // 2. Fast forward and invest (but not enough to reach min)
    let (mut scenario, mut clock, mut settings, mut user_store, mut pod) = init2(TIME_SUBCRIB);
    invest1(&mut pod, &user_store, 500_000, &clock, scenario.ctx());

    // 3. One investor cancels subscription
    scenario.next_tx(investor);
    let refund = pod.cancel_subscription(
        &settings,
        &clock,
        scenario.ctx(),
    );
    assert!(refund.value() > 490_000);
    transfer::public_transfer(refund, @0x0);
    test_scenario::return_shared(pod);

    // 4. Fast forward past subscription end
    clock.increment_for_testing(DAY * 7);

    // 6. Investors get refunds
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let final_refund = pod.failed_pod_refund(&clock, scenario.ctx());
    // After cancel, kept 0.1% of 500_000 = 500, which is fully refunded on failure
    assert_u64_eq(final_refund.value(), 500);
    transfer::public_transfer(final_refund, @0x0);
    test_scenario::return_shared(pod);

    // 7. Founders withdraw tokens
    scenario.next_tx(founder);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let cap = scenario.take_from_sender<PodAdminCap>();
    let withdrawn_tokens = pod.failed_pod_withdraw(
        &cap,
        &clock,
        scenario.ctx(),
    );
    assert_u64_eq(withdrawn_tokens.value(), (MAX_GOAL * PRICE_MULTIPLIER) / TOKEN_PRICE);
    transfer::public_transfer(withdrawn_tokens, @0x0);

    test_scenario::return_to_sender(&scenario, cap);
    cleanup(clock, pod, settings, user_store, scenario);
}
