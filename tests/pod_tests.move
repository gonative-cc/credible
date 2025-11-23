#[allow(unused_let_mut)]
module beelievers_kickstarter::pod_tests;

use beelievers_kickstarter::pod::{
    Self,
    GlobalSettings,
    Pod,
    PodAdminCap,
    ratio_ext_pm,
    ratio_ext,
    init_for_tests,
    create_pod
};
use std::ascii;
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
const SUBS_START_DELTA: u64 = MINUTE; // time delta from "now" to subscription start
const SUBS_DURATION: u64 = DAY * 7;
const VESTING_DURATION: u64 = DAY * 100;
const GRACE_DURATION: u64 = DAY * 3;

// Helper functions for assertions
fun assert_u64_eq(a: u64, b: u64) {
    assert!(a == b, 0);
}

fun assert_u8_eq(a: u8, b: u8) {
    assert!(a == b, 0);
}

/// creates Pod<SUI, SUI>
fun init1(owner: address): (Scenario, Clock, GlobalSettings) {
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
): (Scenario, Clock, GlobalSettings) {
    let mut scenario = test_scenario::begin(owner);
    let mut clock = sui::clock::create_for_testing(scenario.ctx());

    init_for_tests(scenario.ctx());
    scenario.next_tx(owner);

    let subscription_start = clock.timestamp_ms() + SUBS_START_DELTA;
    let tokens = mint_for_testing<SUI>(required_tokens, scenario.ctx());
    let settings = scenario.take_shared<GlobalSettings>();
    let setup_fee = mint_for_testing<SUI>(5_000_000_000, scenario.ctx()); // 5 SUI

    create_pod<SUI, SUI>(
        &settings,
        b"My Project".to_string(),
        b"Great project".to_string(),
        ascii::string(b"https://forum.example.com"),
        token_price,
        price_multiplier,
        min_goal,
        max_goal,
        subscription_start,
        subs_dur,
        vesting_dur,
        immediate_unlock_pm,
        tokens,
        setup_fee,
        &clock,
        scenario.ctx(),
    );

    (scenario, clock, settings)
}

fun cleanup<C, T>(c: Clock, pod: Pod<C, T>, settings: GlobalSettings) {
    test_scenario::return_shared(settings);
    test_scenario::return_shared(pod);
    c.destroy_for_testing();
}

// ================================
// Pod Creation Tests
// ================================

#[test]
fun test_create_pod_success() {
    let owner = @0x1;
    let (mut scenario, clock, mut settings) = init1(owner);

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
    cleanup(clock, pod, settings);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_PARAMS)]
fun test_create_pod_invalid_min_goal() {
    let (mut scenario, c, mut settings) = init_t(
        @0x1,
        REQUIRED_TOKENS,
        TOKEN_PRICE,
        PRICE_MULTIPLIER,
        0, // min_goal = 0 (should fail)
        MAX_GOAL,
        SUBS_DURATION,
        VESTING_DURATION,
        IMMEDIATE_UNLOCK_PM,
    );
    test_scenario::return_shared(settings);
    c.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_PARAMS)]
fun test_create_pod_max_less_than_min() {
    let (mut scenario, c, mut settings) = init_t(
        @0x1,
        REQUIRED_TOKENS,
        TOKEN_PRICE,
        PRICE_MULTIPLIER,
        MAX_GOAL, // reversed arguments
        MIN_GOAL,
        SUBS_DURATION,
        VESTING_DURATION,
        IMMEDIATE_UNLOCK_PM,
    );
    test_scenario::return_shared(settings);
    c.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_PARAMS)]
fun test_create_pod_subscription_duration_too_short() {
    let (mut scenario, c, mut settings) = init_t(
        @0x1,
        REQUIRED_TOKENS,
        TOKEN_PRICE,
        PRICE_MULTIPLIER,
        MIN_GOAL,
        MAX_GOAL,
        DAY * 1, // subscription duration
        VESTING_DURATION,
        IMMEDIATE_UNLOCK_PM,
    );
    test_scenario::return_shared(settings);
    c.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_PARAMS)]
fun test_create_pod_subscription_duration_too_long() {
    let (mut scenario, c, mut settings) = init_t(
        @0x1,
        REQUIRED_TOKENS,
        TOKEN_PRICE,
        PRICE_MULTIPLIER,
        MIN_GOAL,
        MAX_GOAL,
        DAY * 31, // subscription duration > 30 days
        VESTING_DURATION,
        IMMEDIATE_UNLOCK_PM,
    );
    test_scenario::return_shared(settings);
    c.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_PARAMS)]
fun test_create_pod_vesting_duration_too_short() {
    let (mut scenario, c, mut settings) = init_t(
        @0x1,
        REQUIRED_TOKENS,
        TOKEN_PRICE,
        PRICE_MULTIPLIER,
        MIN_GOAL,
        MAX_GOAL,
        SUBS_DURATION,
        DAY * 1, // vesting duration
        IMMEDIATE_UNLOCK_PM,
    );
    test_scenario::return_shared(settings);
    c.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_PARAMS)]
fun test_create_pod_vesting_duration_too_long() {
    let (mut scenario, c, mut settings) = init_t(
        @0x1,
        REQUIRED_TOKENS,
        TOKEN_PRICE,
        PRICE_MULTIPLIER,
        MIN_GOAL,
        MAX_GOAL,
        SUBS_DURATION,
        DAY * 30 * 25, // 25 months > 24 months max
        IMMEDIATE_UNLOCK_PM,
    );
    test_scenario::return_shared(settings);
    c.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_PARAMS)]
fun test_create_pod_immediate_unlock_too_high() {
    let (mut scenario, c, mut settings) = init_t(
        @0x1,
        REQUIRED_TOKENS,
        TOKEN_PRICE,
        PRICE_MULTIPLIER,
        MIN_GOAL,
        MAX_GOAL,
        SUBS_DURATION,
        VESTING_DURATION,
        110, // 11% > 10% max (should fail)
    );
    test_scenario::return_shared(settings);
    c.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pod::E_INVALID_TOKEN_SUPPLY)]
fun test_create_pod_wrong_token_supply() {
    let (mut scenario, c, mut settings) = init_t(
        @0x1,
        REQUIRED_TOKENS / 2, // Provide less tokens (should fail)
        TOKEN_PRICE,
        PRICE_MULTIPLIER,
        MIN_GOAL,
        MAX_GOAL,
        SUBS_DURATION,
        VESTING_DURATION,
        IMMEDIATE_UNLOCK_PM,
    );
    test_scenario::return_shared(settings);
    c.destroy_for_testing();
    scenario.end();
}

// ================================
// Investment Tests
// ================================

#[test]
fun test_successful_investment() {
    let founder = @0x1;
    let investor = @0x2;

    let (mut scenario, mut clock, settings) = init1(founder);

    // Fast forward to subscription period
    scenario.next_tx(founder);
    clock.increment_for_testing(MINUTE * 2);

    // Investor makes investment makes investment
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment = mint_for_testing(100_000, scenario.ctx());
    let excess = pod.invest(investment, &clock, scenario.ctx());

    // Verify no excess returned
    assert_u64_eq(excess.value(), 0);
    transfer::public_transfer(excess, @0x0);

    // Verify investment was recorded
    assert_u64_eq(pod.pod_total_allocated(), (100_000 * PRICE_MULTIPLIER) / TOKEN_PRICE);

    cleanup(clock, pod, settings);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pod::E_POD_NOT_SUBSCRIPTION)]
fun test_invest_before_subscription() {
    let founder = @0x1;
    let investor = @0x2;

    let (mut scenario, clock, settings) = init1(founder);

    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment = mint_for_testing(100_000, scenario.ctx());
    let _excess = pod.invest(investment, &clock, scenario.ctx());
    transfer::public_transfer(_excess, @0x0);

    cleanup(clock, pod, settings);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pod::E_POD_NOT_SUBSCRIPTION)]
fun test_invest_after_subscription_end() {
    let founder = @0x1;
    let investor = @0x2;

    let (mut scenario, mut clock, settings) = init1(founder);

    // Fast forward past subscription end
    scenario.next_tx(founder);
    // Subscription is 7days, starts in 1min, so 8days is enouh
    clock.increment_for_testing(SUBS_DURATION + DAY);

    // Try to invest after subscription ends (should fail)
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment = mint_for_testing(100_000, scenario.ctx());
    let _excess = pod.invest(investment, &clock, scenario.ctx());
    transfer::public_transfer(_excess, @0x0);

    cleanup(clock, pod, settings);
    scenario.end();
}

#[test]
fun test_max_goal_reached_early() {
    let founder = @0x1;
    let investor1 = @0x2;
    let investor2 = @0x3;

    let (mut scenario, mut clock, settings) = init1(founder);

    // Fast forward
    scenario.next_tx(founder);
    clock.increment_for_testing(MINUTE * 2);

    // First investment gets us close to max
    scenario.next_tx(investor1);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment1 = mint_for_testing(900_000, scenario.ctx());
    let excess1 = pod.invest(investment1, &clock, scenario.ctx());
    assert_u64_eq(excess1.value(), 0);
    transfer::public_transfer(excess1, @0x0);
    test_scenario::return_shared(pod);

    // Second investment exceeds max, excess returned
    scenario.next_tx(investor2);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment2 = mint_for_testing(200_000, scenario.ctx());
    let excess2 = pod.invest(investment2, &clock, scenario.ctx());

    // Should have 100_000 excess
    assert_u64_eq(excess2.value(), 100_000);
    let params = pod.get_pod_params();
    assert_u64_eq(pod.get_pod_total_raised(), MAX_GOAL);
    assert_u64_eq(params.get_pod_subscription_end(), clock.timestamp_ms());
    transfer::public_transfer(excess2, @0x0);

    cleanup(clock, pod, settings);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pod::E_POD_NOT_SUBSCRIPTION)]
fun test_invest_after_max_goal() {
    let founder = @0x1;
    let investor1 = @0x2;
    let investor2 = @0x3;

    let (mut scenario, mut clock, settings) = init1(founder);

    // Fast forward
    scenario.next_tx(founder);
    clock.increment_for_testing(MINUTE * 2);

    // First investment reaches max
    scenario.next_tx(investor1);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment1 = mint_for_testing(1_000_000, scenario.ctx());
    let excess1 = pod.invest(investment1, &clock, scenario.ctx());
    transfer::public_transfer(excess1, @0x0);
    test_scenario::return_shared(pod);

    // Second investment should fail
    scenario.next_tx(investor2);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment2 = mint_for_testing(100_000, scenario.ctx());
    let _excess = pod.invest(investment2, &clock, scenario.ctx());
    transfer::public_transfer(_excess, @0x0);

    cleanup(clock, pod, settings);
    scenario.end();
}

#[test]
fun test_multiple_investments_same_investor() {
    let founder = @0x1;
    let investor = @0x2;

    let (mut scenario, mut clock, settings) = init1(founder);

    // Fast forward
    scenario.next_tx(founder);
    clock.increment_for_testing(MINUTE * 2);

    // First investment
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment1 = mint_for_testing(100_000, scenario.ctx());
    let excess1 = pod.invest(investment1, &clock, scenario.ctx());
    transfer::public_transfer(excess1, @0x0);
    test_scenario::return_shared(pod);

    // Second investment from same investor
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment2 = mint_for_testing(50_000, scenario.ctx());
    let excess2 = pod.invest(investment2, &clock, scenario.ctx());
    transfer::public_transfer(excess2, @0x0);

    // Total should be combined
    assert_u64_eq(pod.get_pod_total_raised(), 150_000);

    cleanup(clock, pod, settings);
    scenario.end();
}

#[test]
fun test_cancel_subscription() {
    let founder = @0x1;
    let investor = @0x2;

    let (mut scenario, mut clock, settings) = init1(founder);

    // Fast forward
    scenario.next_tx(founder);
    clock.increment_for_testing(MINUTE * 2);

    // Investor invests
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment = mint_for_testing(100_000, scenario.ctx());
    let excess = pod.invest(investment, &clock, scenario.ctx());
    transfer::public_transfer(excess, @0x0);

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

    cleanup(clock, pod, settings);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pod::E_INVESTMENT_CANCELLED)]
fun test_cancel_subscription_only_once() {
    let founder = @0x1;
    let investor = @0x2;

    let (mut scenario, mut clock, settings) = init1(founder);

    // Fast forward
    scenario.next_tx(founder);
    clock.increment_for_testing(MINUTE * 2);

    // Investor invests and cancels
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment = mint_for_testing(100_000, scenario.ctx());
    let excess = pod.invest(investment, &clock, scenario.ctx());
    transfer::public_transfer(excess, @0x0);
    let refund = pod.cancel_subscription(
        &settings,
        &clock,
        scenario.ctx(),
    );
    transfer::public_transfer(refund, @0x0);
    test_scenario::return_shared(pod);

    // Try to cancel again (should fail)
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let _refund2 = pod.cancel_subscription(
        &settings,
        &clock,
        scenario.ctx(),
    );
    transfer::public_transfer(_refund2, @0x0);

    cleanup(clock, pod, settings);
    scenario.end();
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
    let founder = @0x1;
    let investor = @0x2;

    let (mut scenario, mut clock, settings) = init1(founder);

    // Fast forward to just before subscription ends, then invest
    clock.increment_for_testing(DAY * 7);
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment = mint_for_testing(1_000_000, scenario.ctx());
    let excess = pod.invest(investment, &clock, scenario.ctx());
    transfer::public_transfer(excess, @0x0);
    test_scenario::return_shared(pod);

    // Fast forward past grace to vesting start, then claim
    clock.increment_for_testing(GRACE_DURATION + MINUTE);
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
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

    cleanup(clock, pod, settings);
    scenario.end();
}

#[test]
fun test_founder_claim_funds() {
    let founder = @0x1;
    let investor = @0x2;

    let (mut scenario, mut clock, settings) = init1(founder);

    // Fast forward to just before subscription ends, then invest
    clock.increment_for_testing(DAY * 7);
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment = mint_for_testing(1_000_000, scenario.ctx());
    let excess = pod.invest(investment, &clock, scenario.ctx());
    transfer::public_transfer(excess, @0x0);
    test_scenario::return_shared(pod);

    // Fast forward past grace period, then claim (time elapsed > 0)
    clock.increment_for_testing(DAY * 3 + MINUTE);
    scenario.next_tx(founder);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
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
    cleanup(clock, pod, settings);
    scenario.end();
}

#[test]
fun test_withdraw_unallocated_tokens() {
    let founder = @0x1;
    let investor = @0x2;

    let (mut scenario, mut clock, settings) = init1(founder);

    // Fast forward and invest
    clock.increment_for_testing(MINUTE * 2);
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment = mint_for_testing(800_000, scenario.ctx());
    let excess = pod.invest(investment, &clock, scenario.ctx());
    transfer::public_transfer(excess, @0x0);
    test_scenario::return_shared(pod);

    // Fast forward past grace to vesting
    clock.increment_for_testing(DAY * 7 + DAY * 3);

    // Founder withdraws unallocated tokens
    scenario.next_tx(founder);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let cap = scenario.take_from_sender<PodAdminCap>();

    let unallocated = pod.pod_token_vault_value() - pod.pod_total_allocated();
    let withdrawn = pod.withdraw_unallocated_tokens(
        &cap,
        &clock,
        scenario.ctx(),
    );
    assert_u64_eq(withdrawn.value(), unallocated);
    transfer::public_transfer(withdrawn, @0x0);

    test_scenario::return_to_sender(&scenario, cap);
    cleanup(clock, pod, settings);
    scenario.end();
}

// ================================
// Grace Period Tests
// ================================

#[test]
#[expected_failure(abort_code = pod::E_POD_NOT_VESTING)]
fun test_grace_period_cannot_claim_tokens() {
    let founder = @0x1;
    let investor = @0x2;

    let (mut scenario, mut clock, settings) = init1(founder);

    // Fast forward and invest
    clock.increment_for_testing(MINUTE * 2);
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment = mint_for_testing(MAX_GOAL, scenario.ctx());
    let excess = pod.invest(investment, &clock, scenario.ctx());
    transfer::public_transfer(excess, @0x0);
    test_scenario::return_shared(pod);

    // Fast forward to grace period
    clock.increment_for_testing(GRACE_DURATION / 2);

    // Try to claim tokens (should fail)
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let _claimed = pod.investor_claim_tokens(&clock, scenario.ctx());
    transfer::public_transfer(_claimed, @0x0);

    cleanup(clock, pod, settings);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = pod::E_POD_NOT_VESTING)]
fun test_grace_period_cannot_claim_funds() {
    let founder = @0x1;
    let investor = @0x2;

    let (mut scenario, mut clock, settings) = init1(founder);

    // Fast forward and invest
    clock.increment_for_testing(MINUTE * 2);
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment = mint_for_testing(MAX_GOAL, scenario.ctx());
    let excess = pod.invest(investment, &clock, scenario.ctx());
    transfer::public_transfer(excess, @0x0);
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
    cleanup(clock, pod, settings);
    scenario.end();
}

// ================================
// Exit Mechanism Tests
// ================================

/// Helper to setup pod for exit tests
fun helper_test_exit(is_grace: bool): (Scenario, Clock, GlobalSettings) {
    let founder = @0x1;
    let investor = @0x2;

    let (mut scenario, mut clock, settings) = init1(founder);

    // Fast forward and invest
    clock.increment_for_testing(SUBS_START_DELTA);
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment = mint_for_testing(MAX_GOAL, scenario.ctx());
    let excess = pod.invest(investment, &clock, scenario.ctx());
    transfer::public_transfer(excess, @0x0);
    test_scenario::return_shared(pod);

    // Fast forward to grace or after
    if (is_grace) {
        clock.increment_for_testing(GRACE_DURATION / 2);
    } else {
        clock.increment_for_testing(GRACE_DURATION + DAY);
    };

    (scenario, clock, settings)
}

#[test]
fun test_exit_grace_period() {
    // TODO: add scenario with more than one investor
    // scenario1: single investor taking max goal

    let (mut scenario, clock, s) = helper_test_exit(true);

    // Investor exits during grace
    scenario.next_tx(@0x2);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    assert!(pod.pod_status(&clock) == pod::status_grace());
    let (refund, vested_tokens) = pod.exit_investment(&clock, scenario.ctx());

    let fee = s.get_grace_fee_pm();
    let expected_refund = 1_000_000 - ratio_ext_pm(1_000_000, fee);
    assert_u64_eq(refund.value(), expected_refund);
    assert_u64_eq(vested_tokens.value(), ratio_ext_pm(REQUIRED_TOKENS, fee));
    assert!(pod.pod_status(&clock) == pod::status_grace());
    transfer::public_transfer(refund, @0x0);
    transfer::public_transfer(vested_tokens, @0x0);

    cleanup(clock, pod, s);
    scenario.end();
}

#[test]
fun test_exit_after_grace_period() {
    let (mut scenario, clock, settings) = helper_test_exit(false);

    // Investor exits after grace fee period
    scenario.next_tx(@0x2);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let (refund, vested_tokens) = pod.exit_investment(
        &clock,
        scenario.ctx(),
    );

    // Should get refund with standard 10% fee
    assert!(refund.value() > 0);
    assert!(pod.pod_status(&clock) == pod::status_vesting());
    transfer::public_transfer(refund, @0x0);
    transfer::public_transfer(vested_tokens, @0x0);

    cleanup(clock, pod, settings);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = 1, location = sui::dynamic_field)]
fun test_exit_grace_period_only_once() {
    let (mut scenario, clock, s) = helper_test_exit(true);

    // First exit
    scenario.next_tx(@0x2);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
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

    cleanup(clock, pod, s);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = 1, location = sui::dynamic_field)]
fun test_exit_after_grace_period_only_once() {
    let (mut scenario, clock, settings) = helper_test_exit(false);

    // First exit
    scenario.next_tx(@0x2);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
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

    cleanup(clock, pod, settings);
    scenario.end();
}

// ================================
// Failed Pod Tests
// ================================

#[test]
fun test_failed_pod_refund() {
    let founder = @0x1;
    let investor = @0x2;

    let (mut scenario, mut clock, settings) = init1(founder);

    // Fast forward and invest less than min
    clock.increment_for_testing(MINUTE * 2);
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment = mint_for_testing(500_000, scenario.ctx());
    let excess = pod.invest(investment, &clock, scenario.ctx());
    transfer::public_transfer(excess, @0x0);
    test_scenario::return_shared(pod);

    // Fast forward past subscription end
    clock.increment_for_testing(DAY * 7 + HOUR);

    // Investor gets full refund
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let refund = pod.failed_pod_refund(&clock, scenario.ctx());
    assert_u64_eq(refund.value(), 500_000);
    transfer::public_transfer(refund, @0x0);

    cleanup(clock, pod, settings);
    scenario.end();
}

#[test]
fun test_failed_pod_withdraw_tokens() {
    let founder = @0x1;
    let investor = @0x2;

    let (mut scenario, mut clock, settings) = init1(founder);

    // Fast forward and investor invests less than min
    clock.increment_for_testing(MINUTE * 2);
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment = mint_for_testing(500_000, scenario.ctx());
    let excess = pod.invest(investment, &clock, scenario.ctx());
    transfer::public_transfer(excess, @0x0);
    test_scenario::return_shared(pod);

    // Fast forward to failure
    clock.increment_for_testing(DAY * 7 + HOUR);

    // Founder withdraws all tokens
    scenario.next_tx(founder);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let cap = scenario.take_from_sender<PodAdminCap>();
    let withdrawn = pod.failed_pod_withdraw(&cap, &clock, scenario.ctx());
    assert_u64_eq(withdrawn.value(), (MAX_GOAL * PRICE_MULTIPLIER) / TOKEN_PRICE);
    transfer::public_transfer(withdrawn, @0x0);

    test_scenario::return_to_sender(&scenario, cap);
    cleanup(clock, pod, settings);
    scenario.end();
}

// ================================
// Edge Cases and Boundary Tests
// ================================

#[test]
#[expected_failure(abort_code = pod::E_ZERO_INVESTMENT)]
fun test_zero_investment() {
    let founder = @0x1;
    let investor = @0x2;

    let (mut scenario, mut clock, settings) = init1(founder);

    clock.increment_for_testing(MINUTE * 2);

    // Try to invest 0 (should fail)
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment = mint_for_testing(0, scenario.ctx());
    let _excess = pod.invest(investment, &clock, scenario.ctx());
    transfer::public_transfer(_excess, @0x0);

    cleanup(clock, pod, settings);
    scenario.end();
}

#[test]
fun test_pod_status_transitions() {
    let founder = @0x1;

    let (mut scenario, mut clock, settings) = init1(founder);

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

    cleanup(clock, pod, settings);
    scenario.end();
}

#[test]
fun test_grace_and_vesting_status() {
    let founder = @0x1;

    let (mut scenario, mut clock, settings) = init1(founder);
    scenario.next_tx(founder);
    clock.increment_for_testing(MINUTE * 2);
    scenario.next_tx(founder);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment = mint_for_testing(800_000, scenario.ctx());
    let excess = pod.invest(investment, &clock, scenario.ctx());
    transfer::public_transfer(excess, @0x0);
    test_scenario::return_shared(pod);

    // Fast forward to grace period
    clock.increment_for_testing(DAY * 7);
    scenario.next_tx(founder);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    assert_u8_eq(pod.pod_status(&clock), 3); // GRACE
    test_scenario::return_shared(pod);

    // Fast forward past grace to vesting
    clock.increment_for_testing(DAY * 3);
    scenario.next_tx(founder);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    assert_u8_eq(pod.pod_status(&clock), 4); // VESTING

    cleanup(clock, pod, settings);
    scenario.end();
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

    let (mut scenario, mut clock, settings) = init1(founder);

    // 3. Fast forward to subscription
    clock.increment_for_testing(MINUTE * 2);

    // 4. Multiple investors subscribe
    scenario.next_tx(investor1);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let inv1_investment = mint_for_testing(300_000, scenario.ctx());
    let excess1 = pod.invest(inv1_investment, &clock, scenario.ctx());
    transfer::public_transfer(excess1, @0x0);
    test_scenario::return_shared(pod);

    scenario.next_tx(investor2);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let inv2_investment = mint_for_testing(250_000, scenario.ctx());
    let excess2 = pod.invest(inv2_investment, &clock, scenario.ctx());
    transfer::public_transfer(excess2, @0x0);
    test_scenario::return_shared(pod);

    scenario.next_tx(investor3);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let inv3_investment = mint_for_testing(500_000, scenario.ctx());
    let excess3 = pod.invest(inv3_investment, &clock, scenario.ctx());
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

    cleanup(clock, pod, settings);
    scenario.end();
}

#[test]
fun test_full_pod_lifecycle_failure() {
    let founder = @0x1;
    let investor = @0x2;

    let (mut scenario, mut clock, settings) = init1(founder);

    // 2. Fast forward and invest (but not enough to reach min)
    clock.increment_for_testing(MINUTE * 2);
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let investment = mint_for_testing(500_000, scenario.ctx());
    let excess = pod.invest(investment, &clock, scenario.ctx());
    transfer::public_transfer(excess, @0x0);
    test_scenario::return_shared(pod);

    // 3. One investor cancels subscription
    scenario.next_tx(investor);
    let mut pod = scenario.take_shared<Pod<SUI, SUI>>();
    let refund = pod.cancel_subscription(
        &settings,
        &clock,
        scenario.ctx(),
    );
    assert!(refund.value() > 0);
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
    cleanup(clock, pod, settings);
    scenario.end();
}
