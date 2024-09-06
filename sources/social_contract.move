module leeminhduc2::social_contract {
    use std::error;
    use std::option;
    use std::signer;
    use std::string::utf8;

    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::account::SignerCapability;
    use aptos_framework::resource_account;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_std::pool_u64::Pool;

    /// Only fungible asset metadata owner can make changes.
    const ENOT_OWNER: u64 = 7;
    const EPOOL_NOT_INITIALIZED: u64 = 0;
    const EINVALID_DEDICATED_INITIALIZER: u64 = 4;
    const EINVALID_OWNER: u64 = 5;
    const EUSER_DIDNT_STAKE: u64 = 1;
    const EINVALID_BALANCE: u64 = 2;
    const EINVALID_VALUE: u64 = 3;
    const EINVALID_COIN: u64 = 6;

    const ASSET_NAME : vector<u8> = b"Native FA";

    const ASSET_SYMBOL: vector<u8> = b"NFA";

    const REGISTRATION_FEE: u64 = 100;
    const ACC_PRECISION: u128 = 100000000000;
    const TOKEN_PER_SECOND: u64 = 100;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /// Hold refs to control the minting, transfer and burning of fungible assets.
    struct ManagedFungibleAsset has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        fa_address : address,
    }

    struct StakeInfo has key {
        amount: u64,
        reward_amount: u128,
        reward_debt: u128
    }

    struct PoolInfo has key {
        owner_addr: address,
        acc_reward_per_share: u64,
        token_per_second: u64,
        last_reward_time: u64,
        staker_count: u64,
        stake_fa: u64,
    }

    fun init_module(admin : &signer) {
        let constructor_ref = &object::create_named_object(admin, ASSET_NAME);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            utf8(ASSET_NAME),
            utf8(ASSET_SYMBOL),
            8,
            utf8(b"http://example.com/favicon.ico"), /* icon */
            utf8(b"http://example.com"), /* project */
        );

        // Create mint/burn/transfer refs to allow user to manage the fungible asset.
        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);
        let metadata_object_signer = object::generate_signer(constructor_ref);

        let fa_address = object::create_object_address(&signer::address_of(admin), ASSET_NAME);
        move_to(
            &metadata_object_signer,
            ManagedFungibleAsset { mint_ref, transfer_ref, fa_address },
        );
    }

    public entry fun mint_native_fa(admin : &signer, to : address,  amount : u64) acquires ManagedFungibleAsset {

        // Check if the caller is the owner of the metadata object.
        assert!(signer::address_of(admin) == @leeminhduc2, ENOT_OWNER);

        //
        let asset = get_metadata();
        let managed_fungible_asset = authorized_borrow_refs(admin, asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        let fa = fungible_asset::mint(&managed_fungible_asset.mint_ref, amount);
        fungible_asset::deposit_with_ref(&managed_fungible_asset.transfer_ref, to_wallet, fa);
    }

    public entry fun user_initialize(kol : &signer) {
        let user_address = signer::address_of(kol);

        primary_fungible_store::ensure_primary_store_exists(user_address, get_metadata());
        let current_time = timestamp::now_seconds();
        move_to(kol, PoolInfo {
            owner_addr: user_address,
            acc_reward_per_share: 0,
            token_per_second: TOKEN_PER_SECOND,
            last_reward_time: current_time,
            staker_count: 0,
            stake_fa: 0
        });
    }

    public entry fun user_stake(user: &signer, amount : u64, pool_address  : address ) acquires PoolInfo, StakeInfo {
        assert!(exists<PoolInfo>(pool_address), EPOOL_NOT_INITIALIZED);

        let pool_info = borrow_global_mut<PoolInfo>(pool_address);
        update_pool(pool_info);

        let user_address = signer::address_of(user);
        if (!exists<StakeInfo>(user_address)) {
            move_to<StakeInfo>(user, StakeInfo {
                amount,
                reward_amount: 0,
                reward_debt: 0
            });
            pool_info.staker_count = pool_info.staker_count + 1;
        } else {
            let stake_info = borrow_global_mut<StakeInfo>(user_address);
            update_reward_amount(stake_info, pool_info);
            stake_info.amount = stake_info.amount + amount;
            calculate_reward_debt(stake_info, pool_info);
        };
        pool_info.stake_fa = pool_info.stake_fa + amount;

    }

    public entry fun user_unstake(user: &signer, amount: u64, pool_addr: address) acquires PoolInfo, StakeInfo {
        assert!(exists<PoolInfo>(pool_addr), EPOOL_NOT_INITIALIZED);

        let user_addr = signer::address_of(user);
        assert!(exists<StakeInfo>(user_addr), EUSER_DIDNT_STAKE);

        let pool_info = borrow_global_mut<PoolInfo>(pool_addr);
        update_pool(pool_info);

        let stake_info = borrow_global_mut<StakeInfo>(user_addr);
        assert!(amount <= stake_info.amount, EINVALID_VALUE);
        update_reward_amount(stake_info, pool_info);
        stake_info.amount = stake_info.amount - amount;
        calculate_reward_debt(stake_info, pool_info);

        pool_info.stake_fa = pool_info.stake_fa - amount;
    }

    public entry fun user_register_kol(user : &signer, kol_fa_name : vector<u8>, pool_addr : address) acquires PoolInfo, StakeInfo,  {
        assert!(exists<PoolInfo>(pool_addr), EPOOL_NOT_INITIALIZED);

        let user_addr = signer::address_of(user);
        assert!(exists<StakeInfo>(user_addr), EUSER_DIDNT_STAKE);

        let pool_info = borrow_global_mut<PoolInfo>(pool_addr);
        update_pool(pool_info);

        let stake_info = borrow_global_mut<StakeInfo>(user_addr);
        update_reward_amount(stake_info, pool_info);
        stake_info.amount = stake_info.amount - REGISTRATION_FEE;
        calculate_reward_debt(stake_info, pool_info);

        transfer_native_fa(user, @leeminhduc2, REGISTRATION_FEE);

        // Register KOL here (WIP)

    }

    public entry fun transfer_native_fa(from: &signer, to: address, amount: u64) {
        let from_address = signer::address_of(from);
        let asset = get_metadata();
        let from_wallet = primary_fungible_store::primary_store(from_address, asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        let fa = fungible_asset::withdraw(from,from_wallet, amount);
        fungible_asset::deposit(to_wallet, fa);
    }


    /// Get the metadata object of the fungible asset.
    fun get_metadata() : Object<Metadata> {
        let asset_address = object::create_object_address(&@leeminhduc2, ASSET_NAME);
        object::address_to_object<Metadata>(asset_address)
    }

    /// Borrow the immutable reference of the refs of `metadata `.
    /// This validates that the signer is the metadata object's owner.
    inline fun authorized_borrow_refs(
        owner: &signer,
        asset: Object<Metadata>,
    ): &ManagedFungibleAsset acquires ManagedFungibleAsset {
        assert!(object::is_owner(asset, signer::address_of(owner)), error::permission_denied(ENOT_OWNER));
        borrow_global<ManagedFungibleAsset>(object::object_address(&asset))
    }

    fun update_pool(pool_info: &mut PoolInfo) {
        let current_time = timestamp::now_seconds();
        let passed_seconds = current_time - pool_info.last_reward_time;
        let reward_per_share = 0;
        let pool_total_amount = pool_info.stake_fa;
        if (pool_total_amount != 0)
            reward_per_share = (pool_info.token_per_second as u128) * (passed_seconds as u128) * ACC_PRECISION / (pool_total_amount as u128);
        pool_info.acc_reward_per_share = pool_info.acc_reward_per_share + (reward_per_share as u64);
        pool_info.last_reward_time = current_time;
    }

    fun update_reward_amount(stake_info: &mut StakeInfo, pool_info: &PoolInfo) {
        let pending_reward = (stake_info.amount as u128)
                             * (pool_info.acc_reward_per_share as u128)
                             / ACC_PRECISION
                             - stake_info.reward_debt;
        stake_info.reward_amount = stake_info.reward_amount + pending_reward;
    }

    fun calculate_reward_debt(stake_info: &mut StakeInfo, pool_info: &PoolInfo) {
        stake_info.reward_debt = (stake_info.amount as u128) * (pool_info.acc_reward_per_share as u128) / ACC_PRECISION
    }





}
