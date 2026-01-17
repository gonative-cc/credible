module beelievers_kickstarter::pod;

use std::string::String;
use sui::balance::{Self, Balance};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::dynamic_field as df;
use sui::event::emit;
use sui::sui::SUI;
use sui::table::{Self, Table};

// --- Constants ---
const PERMILLE: u64 = 1000; // For permille calculations
const PERMILLE_U128: u128 = 1000; // For permille calculations

const KeyPodInfo: u8 = 1;

// Pod Statuses
const STATUS_INACTIVE: u8 = 0;
const STATUS_SUBSCRIPTION: u8 = 1;
const STATUS_FAILED: u8 = 2;
const STATUS_GRACE: u8 = 3;
const STATUS_CLIFF: u8 = 4;
const STATUS_VESTING: u8 = 5;

// --- Error Codes ---
const E_POD_NOT_SUBSCRIPTION: u64 = 1;
const E_POD_NOT_VESTING: u64 = 2;
const E_POD_NOT_FAILED: u64 = 3;
const E_INVALID_PARAMS: u64 = 4;
const E_NOT_ADMIN: u64 = 5;
const E_INVESTMENT_NOT_FOUND: u64 = 6;
const E_INVESTMENT_CANCELLED: u64 = 7;
const E_ALREADY_EXITED: u64 = 8;
const E_MAX_GOAL_REACHED: u64 = 9;
const E_NO_SETUP_FEE: u64 = 10;
const E_INVALID_TOKEN_SUPPLY: u64 = 11;
const E_NOTHING_TO_CLAIM: u64 = 12;
const E_NOTHING_TO_EXIT: u64 = 13;
const E_ZERO_INVESTMENT: u64 = 14;
const E_WRONG_URL_LEN: u64 = 15;
const E_WRONG_LEN: u64 = 16;
const E_TC_NOT_ACCEPTED: u64 = 17;
const E_INVALID_TC_VERSION: u64 = 18;

const MAX_URL_LEN: u64 = 48;

//
// --- Module Initialization ---
//
fun init(ctx: &mut TxContext) {
    let day = 1000 * 60 * 60 * 24;
    let settings = GlobalSettings {
        id: object::new(ctx),
        max_immediate_unlock_pm: 100, // 10.0%
        min_vesting_duration: day * 30 * 3, // 3 months
        max_vesting_duration: day * 30 * 24, // 24 months
        min_subscription_duration: day * 7,
        max_subscription_duration: day * 30, // 30 days
        grace_fee_pm: 8, // 0.8%
        grace_duration: 1000 * 60 * 60 * 24 * 3, // 3 days
        cancel_subscription_keep: 1, // 0.1%
        setup_fee: 5_000_000_000, // 5 SUI
        treasury: tx_context::sender(ctx),
        min_cliff_duration: 0, // Cliff duration can be 0 (disabled)
        max_cliff_duration: day * 365 * 2, // 2 years max cliff
    };
    transfer::share_object(settings);

    let user_store = UserStore {
        id: object::new(ctx),
        tc_version: 1, // Initial T&C version
        accepted_tc: table::new(ctx),
    };
    transfer::share_object(user_store);

    let admin_cap = PlatformAdminCap { id: object::new(ctx) };
    transfer::public_transfer(admin_cap, tx_context::sender(ctx));
}

// --- Common Structs ---

/// Capability for updating platform-wide settings.
public struct PlatformAdminCap has key, store { id: UID }

/// Capability for the project team to manage their pod.
public struct PodAdminCap has key, store {
    id: UID,
    pod_id: ID,
}

/// Represents an individual's investment in a pod.
public struct InvestorRecord has copy, drop, store {
    investment: u64,
    allocation: u64,
    claimed_tokens: u64,
    cancelled: bool,
}

public struct PodInfo has copy, drop, store {
    name: String,
    description: String,
    website: String,
    forum_url: String,
    pitch_deck: String,
    business_plan: String,
}

/// The main struct representing a funding campaign.
public struct Pod<phantom C, phantom T> has key {
    id: UID,
    token_vault: Balance<T>,
    funds_vault: Balance<C>,
    total_allocated: u64,
    total_raised: u64,
    num_investors: u64,
    investments: Table<address, InvestorRecord>,
    founder_claimed_funds: u64,
    reached_min_goal: bool,
    params: PodParams,
}

// --- Settings Structs ---

/// Helper struct to store Pod parameters
public struct PodParams has copy, drop, store {
    token_price: u64,
    price_multiplier: u64,
    min_goal: u64,
    max_goal: u64,
    subscription_start: u64,
    subscription_end: u64,
    vesting_duration: u64,
    immediate_unlock_pm: u64,
    grace_fee_pm: u64,
    grace_duration: u64,
    cliff_duration: u64,
    cliff_token_immediate_unlock: bool,
}

/// Shared object containing all platform parameters.
public struct GlobalSettings has key {
    id: UID,
    max_immediate_unlock_pm: u64,
    min_vesting_duration: u64,
    max_vesting_duration: u64,
    min_subscription_duration: u64,
    max_subscription_duration: u64,
    grace_fee_pm: u64,
    grace_duration: u64,
    cancel_subscription_keep: u64,
    setup_fee: u64,
    treasury: address,
    min_cliff_duration: u64,
    max_cliff_duration: u64,
}

/// Shared object for storing user-related data.
public struct UserStore has key {
    id: UID,
    tc_version: u16,
    accepted_tc: Table<address, u16>,
}

public fun get_global_settings(
    settings: &GlobalSettings,
): (u64, u64, u64, u64, u64, u64, u64, u64, u64, address, u64, u64) {
    (
        settings.max_immediate_unlock_pm,
        settings.min_vesting_duration,
        settings.max_vesting_duration,
        settings.min_subscription_duration,
        settings.max_subscription_duration,
        settings.grace_fee_pm,
        settings.grace_duration,
        settings.cancel_subscription_keep,
        settings.setup_fee,
        settings.treasury,
        settings.min_cliff_duration,
        settings.max_cliff_duration,
    )
}

public fun get_grace_fee_pm(s: &GlobalSettings): u64 { s.grace_fee_pm }

// --- Platform Admin Functions ---
public fun update_settings(
    settings: &mut GlobalSettings,
    _: &PlatformAdminCap,
    max_immediate_unlock_pm: Option<u64>,
    min_vesting_duration: Option<u64>,
    max_vesting_duration: Option<u64>,
    min_subscription_duration: Option<u64>,
    max_subscription_duration: Option<u64>,
    grace_fee_pm: Option<u64>,
    grace_duration: Option<u64>,
    cancel_subscription_keep: Option<u64>,
    setup_fee: Option<u64>,
    treasury: Option<address>,
    min_cliff_duration: Option<u64>,
    max_cliff_duration: Option<u64>,
    _ctx: &mut TxContext,
) {
    if (option::is_some(&max_immediate_unlock_pm)) {
        settings.max_immediate_unlock_pm = option::destroy_some(max_immediate_unlock_pm);
    };
    if (option::is_some(&min_vesting_duration)) {
        let v = option::destroy_some(min_vesting_duration);
        assert!(v > 0, E_INVALID_PARAMS);
        settings.min_vesting_duration = v;
    };
    if (option::is_some(&max_vesting_duration)) {
        let v = option::destroy_some(max_vesting_duration);
        assert!(v > 0, E_INVALID_PARAMS);
        settings.max_vesting_duration = v;
    };
    if (option::is_some(&min_subscription_duration)) {
        settings.min_subscription_duration = option::destroy_some(min_subscription_duration);
    };
    if (option::is_some(&max_subscription_duration)) {
        settings.max_subscription_duration = option::destroy_some(max_subscription_duration);
    };

    if (option::is_some(&grace_fee_pm)) {
        settings.grace_fee_pm = option::destroy_some(grace_fee_pm);
    };
    if (option::is_some(&grace_duration)) {
        settings.grace_duration = option::destroy_some(grace_duration);
    };
    if (option::is_some(&cancel_subscription_keep)) {
        settings.cancel_subscription_keep = option::destroy_some(cancel_subscription_keep);
    };
    if (option::is_some(&setup_fee)) {
        settings.setup_fee = option::destroy_some(setup_fee);
    };
    if (option::is_some(&treasury)) {
        settings.treasury = option::destroy_some(treasury);
    };
    if (option::is_some(&min_cliff_duration)) {
        settings.min_cliff_duration = option::destroy_some(min_cliff_duration);
    };
    if (option::is_some(&max_cliff_duration)) {
        settings.max_cliff_duration = option::destroy_some(max_cliff_duration);
    };
    emit(EventSettingsUpdated {});
}

public fun update_tc(user_store: &mut UserStore, _: &PlatformAdminCap, version: u16) {
    assert!(version == user_store.tc_version + 1, E_INVALID_TC_VERSION);
    user_store.tc_version = version;
}

public fun accept_tc(user_store: &mut UserStore, version: u16, ctx: &mut TxContext) {
    assert!(version == user_store.tc_version, E_INVALID_TC_VERSION);
    let user = tx_context::sender(ctx);
    if (user_store.accepted_tc.contains(user)) {
        let v = &mut user_store.accepted_tc[user];
        *v = version;
    } else {
        user_store.accepted_tc.add(user, version);
    };
    emit(EventTcAccepted { user, version });
}

public fun tc_version(user_store: &UserStore): u16 {
    user_store.tc_version
}

public fun accepted_tc_version(user_store: &UserStore, user: address): Option<u16> {
    if (!user_store.accepted_tc.contains(user)) {
        return option::none()
    };
    option::some(user_store.accepted_tc[user])
}

//
// --- Events ---
//

public struct EventPodCreated has copy, drop { pod_id: ID, founder: address }
public struct EventInvestmentMade has copy, drop {
    pod_id: ID,
    investor: address,
    total_investment: u64,
}
public struct EventPodMaxGoal has copy, drop { pod_id: ID }
public struct EventSubscriptionCancelled has copy, drop {
    pod_id: ID,
    investor: address,
    refunded: u64,
    investment: u64,
    allocation: u64,
}
public struct EventSettingsUpdated has copy, drop {}
public struct EventUnallocatedTokensWithdrawn has copy, drop { pod_id: ID, amount: u64 }
public struct EventExitInvestment has copy, drop {
    pod_id: ID,
    investor: address,
    total_investment: u64,
    total_allocation: u64,
}
public struct EventInvestorClaim has copy, drop {
    pod_id: ID,
    investor: address,
    total_amount: u64,
}
public struct EventFounderClaim has copy, drop { pod_id: ID, total_amount: u64 }
public struct EventFailedPodRefund has copy, drop { pod_id: ID, investor: address }
public struct EventFailedPodWithdraw has copy, drop { pod_id: ID }
public struct EventTcAccepted has copy, drop { user: address, version: u16 }

//
// --- Pod Creation and Management ---
//

#[allow(lint(self_transfer))]
public fun create_pod<C, T>(
    settings: &GlobalSettings,
    name: String,
    description: String,
    website: String,
    forum_url: String,
    pitch_deck: String,
    business_plan: String,
    token_price: u64,
    price_multiplier: u64,
    min_goal: u64,
    max_goal: u64,
    subscription_start: u64,
    subscription_duration: u64,
    vesting_duration: u64,
    immediate_unlock_pm: u64,
    cliff_duration: u64,
    cliff_token_immediate_unlock: bool,
    tokens: Coin<T>,
    setup_fee: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let params_valid = (
        min_goal > 0 &&
            max_goal >= min_goal &&
            subscription_duration >= settings.min_subscription_duration &&
            subscription_duration <= settings.max_subscription_duration &&
            vesting_duration >= settings.min_vesting_duration &&
            vesting_duration <= settings.max_vesting_duration &&
            immediate_unlock_pm <= settings.max_immediate_unlock_pm &&
            cliff_duration >= settings.min_cliff_duration &&
            cliff_duration <= settings.max_cliff_duration &&
            subscription_start > clock.timestamp_ms() &&
            token_price > 0 &&
            price_multiplier > 0,
    );
    assert!(params_valid, E_INVALID_PARAMS);
    let fu_len = forum_url.length();
    let pd_len = pitch_deck.length();
    let bp_len = business_plan.length();
    let w_len = website.length();
    let valid_links = (
        fu_len > 8 && fu_len <= MAX_URL_LEN &&
        pd_len > 8 && pd_len <= MAX_URL_LEN &&
        bp_len > 8 && bp_len <= MAX_URL_LEN &&
        w_len > 8 && w_len <= MAX_URL_LEN,
    );
    assert!(valid_links, E_WRONG_URL_LEN);

    let valid_strings = (
        name.length() >= 4 && name.length() <= 32 &&
            description.length() <= 64,
    );
    assert!(valid_strings, E_WRONG_LEN);

    // cliff_token_immediate_unlock must be false if cliff_duration is 0
    if (cliff_duration == 0) {
        assert!(!cliff_token_immediate_unlock, E_INVALID_PARAMS);
    };

    let subscription_end = subscription_start + subscription_duration;
    let required_tokens = (max_goal * price_multiplier) / token_price;
    let supplied_amount = tokens.value();
    assert!(supplied_amount == required_tokens, E_INVALID_TOKEN_SUPPLY);

    // Check and charge setup fee
    assert!(setup_fee.value() == settings.setup_fee, E_NO_SETUP_FEE);
    transfer::public_transfer(setup_fee, settings.treasury);

    let params = PodParams {
        token_price,
        price_multiplier,
        min_goal,
        max_goal,
        subscription_start,
        subscription_end,
        vesting_duration,
        immediate_unlock_pm,
        grace_fee_pm: settings.grace_fee_pm,
        grace_duration: settings.grace_duration,
        cliff_duration,
        cliff_token_immediate_unlock,
    };
    let mut pod = Pod<C, T> {
        id: object::new(ctx),
        token_vault: tokens.into_balance(),
        funds_vault: balance::zero<C>(),
        investments: table::new(ctx),
        total_allocated: 0,
        total_raised: 0,
        num_investors: 0,
        founder_claimed_funds: 0,
        reached_min_goal: false,
        params,
    };
    let pod_id = object::id(&pod);
    let cap = PodAdminCap { id: object::new(ctx), pod_id };
    let pod_info = PodInfo {
        name,
        website,
        description,
        forum_url,
        pitch_deck,
        business_plan,
    };

    df::add(
        &mut pod.id,
        KeyPodInfo,
        pod_info,
    );

    emit(EventPodCreated { pod_id, founder: ctx.sender() });

    transfer::share_object(pod);
    transfer::public_transfer(cap, ctx.sender());
}

// --- Public View Functions ---

public fun get_pod_params<C, T>(pod: &Pod<C, T>): PodParams { pod.params }

public fun get_pod_info<C, T>(pod: &Pod<C, T>): PodInfo {
    *df::borrow<u8, PodInfo>(&pod.id, KeyPodInfo)
}

public fun get_pod_total_raised<C, T>(p: &Pod<C, T>): u64 { p.total_raised }

public fun get_pod_num_investors<C, T>(p: &Pod<C, T>): u64 { p.num_investors }

public fun get_pod_token_price(p: &PodParams): u64 { p.token_price }

public fun get_pod_price_multiplier(p: &PodParams): u64 { p.price_multiplier }

public fun get_pod_min_goal(p: &PodParams): u64 { p.min_goal }

public fun get_pod_max_goal(p: &PodParams): u64 { p.max_goal }

public fun get_pod_subscription_start(p: &PodParams): u64 { p.subscription_start }

public fun get_pod_subscription_end(p: &PodParams): u64 { p.subscription_end }

public fun get_pod_vesting_duration(p: &PodParams): u64 { p.vesting_duration }

public fun get_pod_immediate_unlock_pm(p: &PodParams): u64 { p.immediate_unlock_pm }

public fun get_pod_grace_fee_pm(p: &PodParams): u64 { p.grace_fee_pm }

public fun get_pod_grace_duration(p: &PodParams): u64 { p.grace_duration }

public fun get_pod_cliff_duration(p: &PodParams): u64 { p.cliff_duration }

public fun get_pod_cliff_token_immediate_unlock(p: &PodParams): bool {
    p.cliff_token_immediate_unlock
}

public fun pod_token_vault_value<C, T>(pod: &Pod<C, T>): u64 {
    pod.token_vault.value()
}

public fun pod_total_allocated<C, T>(pod: &Pod<C, T>): u64 { pod.total_allocated }

public fun pod_status<C, T>(pod: &Pod<C, T>, clock: &Clock): u8 {
    let now = clock.timestamp_ms();
    if (now < pod.params.subscription_start) return STATUS_INACTIVE;
    if (now < pod.params.subscription_end) return STATUS_SUBSCRIPTION;
    if (!pod.reached_min_goal) return STATUS_FAILED;

    let grace_end = pod.params.subscription_end + pod.params.grace_duration;
    if (now < grace_end) return STATUS_GRACE;
    if (pod.params.cliff_duration > 0) {
        let cliff_end = grace_end + pod.params.cliff_duration;
        if (now < cliff_end) return STATUS_CLIFF;
    };
    STATUS_VESTING
}

/// returns Some(InvestorRecord) for the investor if he invest in the pod.
/// Otherwise returns None.
public fun investor_record<C, T>(pod: &Pod<C, T>, investor: address): Option<InvestorRecord> {
    if (!pod.investments.contains(investor)) return option::none();

    option::some(pod.investments[investor])
}

//
// --- Investor Functions ---
//

public fun invest<C, T>(
    pod: &mut Pod<C, T>,
    user_store: &UserStore,
    mut investment: Coin<C>,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<C> {
    assert!(pod_status(pod, clock) == STATUS_SUBSCRIPTION, E_POD_NOT_SUBSCRIPTION);
    assert!(pod.total_raised < pod.params.max_goal, E_MAX_GOAL_REACHED);

    let investment_amount = investment.value();
    assert!(investment_amount > 0, E_ZERO_INVESTMENT);
    let investor = ctx.sender();
    let accepted_version = if (user_store.accepted_tc.contains(investor)) {
        user_store.accepted_tc[investor]
    } else {
        0
    };
    assert!(accepted_version >= user_store.tc_version, E_TC_NOT_ACCEPTED);
    let new_total_raised = pod.total_raised + investment_amount;

    let (actual_investment, excess_coin) = if (new_total_raised > pod.params.max_goal) {
        let excess = new_total_raised - pod.params.max_goal;
        let actual = investment_amount - excess;
        (actual, investment.split(excess, ctx))
    } else {
        (investment_amount, coin::zero(ctx))
    };

    let additional_tokens = ratio_ext(
        pod.params.price_multiplier,
        actual_investment,
        pod.params.token_price,
    );
    pod.total_raised = pod.total_raised + actual_investment;
    if (pod.total_raised >= pod.params.min_goal && !pod.reached_min_goal) {
        pod.reached_min_goal = true;
    };
    pod.total_allocated = pod.total_allocated + additional_tokens;
    pod.funds_vault.join(investment.into_balance());

    let total_investment = if (pod.investments.contains(investor)) {
        let ir = &mut pod.investments[investor];
        ir.investment = ir.investment + actual_investment;
        ir.allocation = ir.allocation + additional_tokens;
        ir.investment
    } else {
        let allocation = InvestorRecord {
            investment: actual_investment,
            allocation: additional_tokens,
            claimed_tokens: 0,
            cancelled: false,
        };
        pod.investments.add(investor, allocation);
        pod.num_investors = pod.num_investors + 1;
        actual_investment
    };

    let pod_id = object::id(pod);
    emit(EventInvestmentMade { pod_id, investor, total_investment });

    if (pod.total_raised >= pod.params.max_goal) {
        // This triggers grace/vesting
        pod.params.subscription_end = clock::timestamp_ms(clock);
        emit(EventPodMaxGoal { pod_id });
    };

    excess_coin
}

/// Cancels an investor's subscription. Reduces the investment to the fee amount.
/// Can be called only once.
public fun cancel_subscription<C, T>(
    pod: &mut Pod<C, T>,
    settings: &GlobalSettings,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<C> {
    assert!(pod_status(pod, clock) == STATUS_SUBSCRIPTION, E_POD_NOT_SUBSCRIPTION);

    let investor = ctx.sender();
    assert!(pod.investments.contains(investor), E_INVESTMENT_NOT_FOUND);
    let pod_id = object::id(pod);
    let ir = &mut pod.investments[investor];
    assert!(!ir.cancelled, E_INVESTMENT_CANCELLED);

    let orig_investment = ir.investment;
    let orig_allocation = ir.allocation;
    // NOTE: no need to use higher precision because the cancel_subscription_keep is small
    ir.investment = (orig_investment * settings.cancel_subscription_keep) / PERMILLE;
    ir.allocation = (orig_allocation * settings.cancel_subscription_keep) / PERMILLE;
    ir.cancelled = true;

    let refunded = orig_investment - ir.investment;
    pod.total_raised = pod.total_raised - refunded;
    let allocation_reduction = orig_allocation - ir.allocation;
    pod.total_allocated = pod.total_allocated - allocation_reduction;

    emit(EventSubscriptionCancelled {
        pod_id,
        investor,
        refunded,
        investment: ir.investment,
        allocation: ir.allocation,
    });
    coin::take(&mut pod.funds_vault, refunded, ctx)
}

public fun investor_claim_tokens<C, T>(
    pod: &mut Pod<C, T>,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<T> {
    let status = pod_status(pod, clock);
    assert!(status == STATUS_VESTING || status == STATUS_CLIFF, E_POD_NOT_VESTING);
    let investor = ctx.sender();
    let pod_id = object::id(pod);
    let time_elapsed = pod.elapsed_vesting_time(clock);
    let ir = &mut pod.investments[investor];
    let vested_tokens = calculate_vested_tokens(
        time_elapsed,
        pod.params.vesting_duration,
        pod.params.immediate_unlock_pm,
        ir.allocation,
    );

    let to_claim = vested_tokens - ir.claimed_tokens;
    assert!(to_claim > 0, E_NOTHING_TO_CLAIM);

    ir.claimed_tokens = ir.claimed_tokens + to_claim;
    emit(EventInvestorClaim { pod_id, investor, total_amount: ir.claimed_tokens });

    coin::take(&mut pod.token_vault, to_claim, ctx)
}

public fun exit_investment<C, T>(
    pod: &mut Pod<C, T>,
    clock: &Clock,
    ctx: &mut TxContext,
): (Coin<C>, Coin<T>) {
    let status = pod.pod_status(clock);
    assert!(
        status == STATUS_GRACE || status == STATUS_CLIFF || status == STATUS_VESTING,
        E_POD_NOT_VESTING,
    );
    let investor = ctx.sender();
    // we delete the investment record to assure user won't be able to exit 2 times.
    let ir = pod.investments.remove(investor);
    pod.num_investors = pod.num_investors - 1;
    assert!(ir.claimed_tokens < ir.allocation, E_ALREADY_EXITED);

    let (vested_tokens, funds_unlocked) = if (status == STATUS_GRACE) {
        let vested_tokens = ratio_ext_pm(ir.allocation, pod.params.grace_fee_pm);
        (vested_tokens, 0)
    } else if (status == STATUS_CLIFF) {
        // During cliff, no additional tokens have vested beyond immediate unlock
        // Investors get their immediate unlock tokens, but no additional vesting happens
        let vested_tokens = ratio_ext_pm(ir.allocation, pod.params.immediate_unlock_pm);
        (vested_tokens, 0)
    } else {
        // STATUS_VESTING
        let time_elapsed = pod.elapsed_vesting_time(clock);
        let vested_tokens = calculate_vested_tokens(
            time_elapsed,
            pod.params.vesting_duration,
            pod.params.immediate_unlock_pm,
            ir.allocation,
        );
        let funds_unlocked = calculate_vested_tokens(
            time_elapsed,
            pod.params.vesting_duration,
            pod.params.immediate_unlock_pm,
            ir.investment,
        );
        (vested_tokens, funds_unlocked)
    };

    let fee_pm = if (status == STATUS_GRACE) {
        pod.params.grace_fee_pm
    } else {
        pod.params.immediate_unlock_pm
    };

    let remaining_investment = ir.investment - funds_unlocked;
    let fee_amount = ratio_ext_pm(remaining_investment, fee_pm);
    assert!(remaining_investment > fee_amount, E_NOTHING_TO_EXIT);

    let refund_amount = remaining_investment - fee_amount;
    pod.total_raised = pod.total_raised - refund_amount;
    let refund_coin = coin::take(&mut pod.funds_vault, refund_amount, ctx);

    let to_claim = vested_tokens - ir.claimed_tokens;
    let vested_coin = if (to_claim > 0) {
        coin::take(&mut pod.token_vault, to_claim, ctx)
    } else {
        coin::zero(ctx)
    };

    // reminder of the tokens allocated to the investors should decrease the total_allocation,
    // so they can be claimed by the founders.
    let unvested_tokens = ir.allocation - vested_tokens;
    if (unvested_tokens > 0) {
        pod.total_allocated = pod.total_allocated - unvested_tokens;
    };

    emit(EventExitInvestment {
        pod_id: object::id(pod),
        investor,
        total_investment: funds_unlocked+fee_amount,
        total_allocation: vested_tokens,
    });

    (refund_coin, vested_coin)
}

public fun failed_pod_refund<C, T>(
    pod: &mut Pod<C, T>,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<C> {
    assert!(pod_status(pod, clock) == STATUS_FAILED, E_POD_NOT_FAILED);
    let investor = ctx.sender();
    let ir = pod.investments.remove(investor);

    emit(EventFailedPodRefund { pod_id: object::id(pod), investor });
    coin::take(&mut pod.funds_vault, ir.investment, ctx)
}

//
// --- Founder Functions ---
//

public fun founder_claim_funds<C, T>(
    pod: &mut Pod<C, T>,
    cap: &PodAdminCap,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<C> {
    let pod_id = object::id(pod);
    assert!(cap.pod_id == pod_id, E_NOT_ADMIN);
    let status = pod.pod_status(clock);
    assert!(status == STATUS_VESTING || status == STATUS_CLIFF, E_POD_NOT_VESTING);

    let total_claimable = calculate_founder_claimable(pod, clock);
    let to_claim = total_claimable - pod.founder_claimed_funds;
    assert!(to_claim > 0, E_NOTHING_TO_CLAIM);

    pod.founder_claimed_funds = pod.founder_claimed_funds + to_claim;
    emit(EventFounderClaim {
        pod_id,
        total_amount: pod.founder_claimed_funds,
    });
    coin::take(&mut pod.funds_vault, to_claim, ctx)
}

public fun failed_pod_withdraw<C, T>(
    pod: &mut Pod<C, T>,
    cap: &PodAdminCap,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<T> {
    let pod_id = object::id(pod);
    assert!(cap.pod_id == pod_id, E_NOT_ADMIN);
    assert!(pod_status(pod, clock) == STATUS_FAILED, E_POD_NOT_FAILED);

    emit(EventFailedPodWithdraw { pod_id });
    coin::from_balance(pod.token_vault.withdraw_all(), ctx)
}

/// Enable founders to withdraw unallocated tokens
public fun founder_claim_unallocated_tokens<C, T>(
    pod: &mut Pod<C, T>,
    cap: &PodAdminCap,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<T> {
    let pod_id = object::id(pod);
    assert!(cap.pod_id == pod_id, E_NOT_ADMIN);
    assert!(pod_status(pod, clock) == STATUS_VESTING, E_POD_NOT_VESTING);

    let amount = pod.token_vault.value() - pod.total_allocated;
    assert!(amount > 0, E_NOTHING_TO_CLAIM);
    emit(EventUnallocatedTokensWithdrawn { pod_id, amount });

    coin::take(&mut pod.token_vault, amount, ctx)
}

// --- Public View Functions ---

public fun calculate_founder_claimable<C, T>(pod: &Pod<C, T>, clock: &Clock): u64 {
    let status = pod.pod_status(clock);
    if (status == STATUS_VESTING) {
        let time_elapsed = pod.elapsed_vesting_time(clock);
        calculate_vested_tokens(
            time_elapsed,
            pod.params.vesting_duration,
            pod.params.immediate_unlock_pm,
            pod.total_raised,
        )
    } else if (status == STATUS_CLIFF) {
        // During cliff, only immediate_unlock is available
        ratio_ext_pm(pod.total_raised, pod.params.immediate_unlock_pm)
    } else {
        0 // Not in cliff or vesting, so nothing claimable
    }
}

// Note: we can't have it as a pod method because it cause problem with borrow constrains.
public fun calculate_vested_tokens(
    time_elapsed: u64,
    vesting_duration: u64,
    immediate_unlock_pm: u64,
    allocation: u64,
): u64 {
    let immediate_unlock = ratio_ext_pm(allocation, immediate_unlock_pm);
    if (time_elapsed == 0) return immediate_unlock;

    if (time_elapsed >= vesting_duration) {
        return allocation
    };
    let vested_tokens = ratio_ext(
        time_elapsed,
        (allocation - immediate_unlock),
        vesting_duration,
    );
    return immediate_unlock + vested_tokens
}

//
// --- Package Helper Functions ---
//

/// Returns time elapsed since vesting when pod is in Vesting phase.
/// Returns zero when pod is in Cliff phase with cliff_token_immediate_unlock == true.
/// Aborts otherwise.
public(package) fun elapsed_vesting_time<C, T>(pod: &Pod<C, T>, clock: &Clock): u64 {
    let status = pod_status(pod, clock);
    assert!(status == STATUS_VESTING || status == STATUS_CLIFF, E_POD_NOT_VESTING);
    if (status == STATUS_CLIFF) {
        assert!(pod.params.cliff_token_immediate_unlock, E_POD_NOT_VESTING);
        return 0
    };
    let now = clock.timestamp_ms();
    let vesting_start =
        pod.params.subscription_end + pod.params.grace_duration + pod.params.cliff_duration;
    now - vesting_start
}

/// calculates num * numerator / denominator using extended precision (u128)
public fun ratio_ext(x: u64, numerator: u64, denominator: u64): u64 {
    ((x as u128) * (numerator as u128) / (denominator as u128)) as u64
}

/// calculates num * numerator / PERMILLE using extended precision (u128)
public fun ratio_ext_pm(x: u64, numerator: u64): u64 {
    ((x as u128) * (numerator as u128) / PERMILLE_U128) as u64
}

//
// --- Tests ---
//

#[test_only]
public fun init_for_tests(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun status_inactive(): u8 { STATUS_INACTIVE }
#[test_only]
public fun status_subscription(): u8 { STATUS_SUBSCRIPTION }
#[test_only]
public fun status_failed(): u8 { STATUS_FAILED }
#[test_only]
public fun status_grace(): u8 { STATUS_GRACE }
#[test_only]
public fun status_cliff(): u8 { STATUS_CLIFF }
#[test_only]
public fun status_vesting(): u8 { STATUS_VESTING }
