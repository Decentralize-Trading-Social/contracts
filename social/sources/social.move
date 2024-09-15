module social::social {
  use std::signer;
  use aptos_framework::object::{Self, Object, TransferRef, ObjectCore};
  use aptos_framework::primary_fungible_store::{Self};
  use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata, 
      MutateMetadataRef as FungibleMutateMetadataRef,
      BurnRef as FungibleBurnRef,
      MintRef as FungibleMintRef, 
      TransferRef as FungibleTransferRef};
  use aptos_std::math64::{Self};
  use aptos_framework::smart_table::{Self, SmartTable};
  use aptos_framework::block::{Self};
  use std::string::{Self, String};
  use std::option;
  use std::vector::{Self};
  use aptos_framework::smart_vector::{Self, SmartVector};

  const ASSET_NAME: vector<u8> = b"social";
  const ASSET_SYMBOL: vector<u8> = b"SOCIAL";

  const E_ALREADY_FOLLOWED: u64 = 1;
  const E_ALREADY_FOLLOWING: u64 = 2;
  const E_NOT_FOLLOWED: u64 = 3;
  const E_NOT_FOLLOWING: u64 = 4;

  #[event]
  struct StakeNative has drop, store {
    user_address: address,
    amount: u64,
  }

  #[event]
  struct RegisterKol has drop, store {
    user_address: address,
    kol_address: address,
    amount: u64,
  }
  
  struct ProtocolManagedFA has store, drop, key {
    mutate_ref: FungibleMutateMetadataRef,
    transfer_ref: FungibleTransferRef,
    mint_ref: FungibleMintRef,
    burn_ref: FungibleBurnRef,
  }

  struct ProtocolConfig has key, copy {
    minimum_stake: u64,
    maximum_stake: u64,
    mint_per_block: u64,
  }

  struct ProtocolStakerInfo has store, key, drop, copy {
    stake_amount: u64,
    last_action_block: u64,
    pending_reward: u64,
  }

  struct ProtocolData has key {
    stakers: SmartTable<address, ProtocolStakerInfo>,
  }

  struct KOLInfo has key {
    kol: address,
  }

  struct KOLConfig has key, copy {
    minimum_stake: u64,
  }

  struct KOLStakerInfo has store, key, drop {
    stake_amount: u64, 
  }

  struct KOLData has key {
    stakers: SmartTable<address, KOLStakerInfo>,
  }

  struct KOLManagedFa has store, drop, key {
    mutate_ref: FungibleMutateMetadataRef,
    transfer_ref: FungibleTransferRef,
    mint_ref: FungibleMintRef,
    burn_ref: FungibleBurnRef,
  }

  struct AdminInfo has drop, key {
    admin: address,
  }

  struct Post has store, copy {
    post_content: String,
    post_image: vector<String>,
  }

  struct UploadPosts has key {
    posts: SmartVector<Post>,
  }

  struct FollowData has key, store {
    followers: SmartTable<address, SmartVector<address>>,
    following: SmartTable<address, SmartVector<address>>,
  }

  fun init_module(account_signer: &signer) {
    let protocol_fa_metadata_constructor_ref = object::create_named_object(account_signer, b"social");
    primary_fungible_store::create_primary_store_enabled_fungible_asset(
      &protocol_fa_metadata_constructor_ref,
      option::none(),
      string::utf8(ASSET_NAME),
      string::utf8(ASSET_SYMBOL),
      8,
      string::utf8(b"social"),
      string::utf8(b"social"),
    );
    let transfer_ref = fungible_asset::generate_transfer_ref(&protocol_fa_metadata_constructor_ref);
    let mint_ref = fungible_asset::generate_mint_ref(&protocol_fa_metadata_constructor_ref);
    let burn_ref = fungible_asset::generate_burn_ref(&protocol_fa_metadata_constructor_ref);
    let mutate_ref = fungible_asset::generate_mutate_metadata_ref(&protocol_fa_metadata_constructor_ref);
    move_to(&object::generate_signer(&protocol_fa_metadata_constructor_ref), ProtocolManagedFA {
      mutate_ref,
      transfer_ref,
      mint_ref,
      burn_ref,
    });
    move_to(account_signer, ProtocolConfig {
      minimum_stake: 100_000_000,
      maximum_stake: 10_000_000_000,
      mint_per_block: 1000000,
    });
    move_to(account_signer, ProtocolData {
      stakers: smart_table::new<address, ProtocolStakerInfo>(),
    });

    // Initialize follow data
    move_to(account_signer, FollowData {
      followers: smart_table::new<address, SmartVector<address>>(),
      following: smart_table::new<address, SmartVector<address>>(),
    });
  }

  entry public fun first_time_stake_native(account_signer: &signer, user_address: String, amount: u64, minimum_stake_config: u64) acquires ProtocolConfig, ProtocolData, ProtocolManagedFA {
    assert!(!object::object_exists<Metadata>(object::create_object_address(&signer::address_of(account_signer), b"social")), 2);
    let metadata_constructore_ref = object::create_named_object(account_signer, b"social");
    primary_fungible_store::create_primary_store_enabled_fungible_asset(
      &metadata_constructore_ref,
      option::none(),
      user_address,
      user_address,
      8,
      string::utf8(b"KOL"),
      string::utf8(b"KOL"),
    );
    let metadata_signer = object::generate_signer(&metadata_constructore_ref);
    move_to(&metadata_signer, KOLInfo {
      kol: signer::address_of(account_signer),
    });
    move_to(&metadata_signer, KOLManagedFa {
      mutate_ref: fungible_asset::generate_mutate_metadata_ref(&metadata_constructore_ref),
      transfer_ref: fungible_asset::generate_transfer_ref(&metadata_constructore_ref),
      mint_ref: fungible_asset::generate_mint_ref(&metadata_constructore_ref),
      burn_ref: fungible_asset::generate_burn_ref(&metadata_constructore_ref),
    });
    let config = borrow_global<ProtocolConfig>(@social);
    let data = borrow_global_mut<ProtocolData>(@social);
    let protocol_fa_address = object::create_object_address(&@social, b"social");
    
    let managed_fa = borrow_global<ProtocolManagedFA>(protocol_fa_address);
    let native_metadata_object = fungible_asset::transfer_ref_metadata(&managed_fa.transfer_ref);
    primary_fungible_store::transfer<Metadata>(
      account_signer,
      native_metadata_object,
      @social,
      amount,
    );

    let current_block = block::get_current_block_height();
    let info = smart_table::borrow_mut_with_default<address, ProtocolStakerInfo>(
      &mut data.stakers,
      signer::address_of(account_signer),
      ProtocolStakerInfo {
        stake_amount: 0,
        last_action_block: current_block,
        pending_reward: 0,
      },
    );

    let new_stake_amount = info.stake_amount + amount;
    assert!(new_stake_amount >= config.minimum_stake, 101);
    assert!(new_stake_amount <= config.maximum_stake, 102);

    let available_reward = config.mint_per_block * (current_block - info.last_action_block);
    let new_reward = info.pending_reward + math64::mul_div(info.stake_amount, available_reward, config.maximum_stake);
    smart_table::upsert<address, ProtocolStakerInfo>(
      &mut data.stakers,
      signer::address_of(account_signer),
      ProtocolStakerInfo {
        stake_amount: new_stake_amount,
        last_action_block: current_block,
        pending_reward: new_reward,
      },
    );
    move_to(account_signer, KOLConfig {
      minimum_stake: minimum_stake_config,
    });
    move_to(account_signer, KOLData {
      stakers: smart_table::new<address, KOLStakerInfo>(),
    });
    0x1::event::emit(StakeNative {
      user_address: signer::address_of(account_signer),
      amount,
    });
  }

  // Stake native token to the protocol to become a kol, user_address must be full address
  entry public fun stake_native(account_signer: &signer, amount: u64) acquires ProtocolData, ProtocolConfig, ProtocolManagedFA {
    assert!(object::object_exists<Metadata>(object::create_object_address(&signer::address_of(account_signer), b"social")), 3);
    let config = borrow_global<ProtocolConfig>(@social);
    let data = borrow_global_mut<ProtocolData>(@social);
    let protocol_fa_address = object::create_object_address(&@social, b"social");
    
    let managed_fa = borrow_global<ProtocolManagedFA>(protocol_fa_address);
    let native_metadata_object = fungible_asset::transfer_ref_metadata(&managed_fa.transfer_ref);
    primary_fungible_store::transfer<Metadata>(
      account_signer,
      native_metadata_object,
      @social,
      amount,
    );

    let current_block = block::get_current_block_height();
    let info = smart_table::borrow_mut<address, ProtocolStakerInfo>(
      &mut data.stakers,
      signer::address_of(account_signer),
    );

    let new_stake_amount = info.stake_amount + amount;
    assert!(new_stake_amount >= config.minimum_stake, 101);
    assert!(new_stake_amount <= config.maximum_stake, 102);

    let available_reward = config.mint_per_block * (current_block - info.last_action_block);
    let new_reward = info.pending_reward + math64::mul_div(info.stake_amount, available_reward, config.maximum_stake);
    smart_table::upsert<address, ProtocolStakerInfo>(
      &mut data.stakers,
      signer::address_of(account_signer),
      ProtocolStakerInfo {
        stake_amount: new_stake_amount,
        last_action_block: current_block,
        pending_reward: new_reward,
      },
    );
    0x1::event::emit(StakeNative {
      user_address: signer::address_of(account_signer),
      amount,
    });
  }

  entry public fun register_kol(account_signer: &signer, kol_address: address, amount: u64) acquires KOLData, KOLConfig {
    let kol_fa_address = object::create_object_address(&kol_address, b"social");
    let kol_fa_metadata = object::address_to_object<Metadata>(kol_fa_address);
    let config = borrow_global<KOLConfig>(kol_address);
    let data = borrow_global_mut<KOLData>(kol_address);
    assert!(amount >= config.minimum_stake, 103);
    primary_fungible_store::transfer<Metadata>(
      account_signer,
      kol_fa_metadata,
      kol_address,
      amount,
    );
    let info = smart_table::borrow_mut_with_default<address, KOLStakerInfo>(
      &mut data.stakers,
      signer::address_of(account_signer),
      KOLStakerInfo {
        stake_amount: 0,
      },
    );
    let new_stake_amount = info.stake_amount + amount;
    smart_table::upsert<address, KOLStakerInfo>(
      &mut data.stakers,
      signer::address_of(account_signer),
      KOLStakerInfo {
        stake_amount: new_stake_amount,
      },
    );
    0x1::event::emit(RegisterKol {
      user_address: signer::address_of(account_signer),
      kol_address,
      amount,
    });
  }

  entry public fun collect_reward(account_signer: &signer) acquires ProtocolData, ProtocolConfig, ProtocolManagedFA {
    let config = borrow_global<ProtocolConfig>(@social);
    let data = borrow_global_mut<ProtocolData>(@social);
    let managed_fa = borrow_global<ProtocolManagedFA>(@social);
    let current_block = block::get_current_block_height();
    let info = smart_table::borrow_mut_with_default<address, ProtocolStakerInfo>(
      &mut data.stakers,
      signer::address_of(account_signer),
      ProtocolStakerInfo {
        stake_amount: 0,
        last_action_block: current_block,
        pending_reward: 0,
      },
    );
    let available_reward = config.mint_per_block * (current_block - info.last_action_block);
    let new_reward = info.pending_reward + math64::mul_div(info.stake_amount, available_reward, config.maximum_stake);
    let native_metadata_object = fungible_asset::transfer_ref_metadata(&managed_fa.transfer_ref);
    primary_fungible_store::transfer<Metadata>(
      account_signer,
      native_metadata_object,
      @social,
      new_reward,
    );
    smart_table::upsert<address, ProtocolStakerInfo>(
      &mut data.stakers,
      signer::address_of(account_signer),
      ProtocolStakerInfo {
        stake_amount: info.stake_amount,
        last_action_block: current_block,
        pending_reward: 0,
      },
    );
  }

  entry public fun upload_post(account_signer: &signer, post_content: String, post_image: vector<String>) acquires UploadPosts {
    if (!exists<UploadPosts>(signer::address_of(account_signer))) {
      move_to(account_signer, UploadPosts {
        posts: smart_vector::new<Post>(),
      });
    };
    let data = borrow_global_mut<UploadPosts>(signer::address_of(account_signer));
    smart_vector::push_back<Post>(
      &mut data.posts,
      Post {
        post_content,
        post_image,
      },
    );
  }

  entry public fun follow(from : &signer, to : address) acquires FollowData {
    let data = borrow_global_mut<FollowData>(@social);
    let from_address = signer::address_of(from);
    if (!smart_table::contains<address,SmartVector<address>>(&data.following, from_address)) {
      smart_table::add<address, SmartVector<address>>(&mut data.following, from_address, smart_vector::new<address>());
    };
    if (!smart_table::contains<address,SmartVector<address>>(&data.followers, to)) {
        smart_table::add<address, SmartVector<address>>(&mut data.followers, to, smart_vector::new<address>());
    };
    let following = smart_table::borrow_mut<address,SmartVector<address>>(&mut data.following, from_address);
    let followers = smart_table::borrow_mut<address,SmartVector<address>>(&mut data.followers, to);
    assert!(!smart_vector::contains<address>(following, &to), E_ALREADY_FOLLOWED);
    assert!(!smart_vector::contains<address>(followers, &from_address), E_ALREADY_FOLLOWING);
    smart_vector::push_back<address>(following, to);
    smart_vector::push_back<address>(followers, signer::address_of(from));


  }

  entry public fun unfollow(from : &signer, to : address) acquires FollowData {
    let data = borrow_global_mut<FollowData>(@social);
    let from_address = signer::address_of(from);
    assert!(smart_table::contains<address,SmartVector<address>>(&data.following, from_address), E_NOT_FOLLOWED);
    assert!(smart_table::contains<address,SmartVector<address>>(&data.followers, to), E_NOT_FOLLOWING);
    let following = smart_table::borrow_mut<address,SmartVector<address>>(&mut data.following, from_address);
    let followers = smart_table::borrow_mut<address,SmartVector<address>>(&mut data.followers, to);
    assert!(smart_vector::contains<address>(following, &to), E_NOT_FOLLOWED);
    assert!(smart_vector::contains<address>(followers, &from_address), E_NOT_FOLLOWING);
    let (_, index) = smart_vector::index_of<address>(following, &to);
    smart_vector::remove<address>(following, index);
    let (_, index) = smart_vector::index_of<address>(followers, &from_address);
    smart_vector::remove<address>(followers, index);
  }

  #[view]
  public fun get_kol_config(kol_address: address): KOLConfig acquires KOLConfig {
    *borrow_global<KOLConfig>(kol_address)
  }

  #[view]
  public fun get_protocol_config(): ProtocolConfig acquires ProtocolConfig {
    *borrow_global<ProtocolConfig>(@social)
  }

  #[view]
  public fun get_protocol_stake_amount(account: address): u64 acquires ProtocolData {
    let data = borrow_global<ProtocolData>(@social);
    let info = smart_table::borrow_with_default<address, ProtocolStakerInfo>(&data.stakers, account, 
      &ProtocolStakerInfo {
        stake_amount: 0,
        last_action_block: 0,
        pending_reward: 0,
      },
    );
    info.stake_amount
  }

  #[view]
  public fun get_kol_stake_amount(account: address, kol_address: address): u64 acquires KOLData {
    let data = borrow_global<KOLData>(kol_address);
    let info = smart_table::borrow_with_default<address, KOLStakerInfo>(&data.stakers, account, 
      &KOLStakerInfo {
        stake_amount: 0,
      },
    );
    info.stake_amount
  } 

  #[view]
  public fun get_user_posts(account: address): vector<Post> acquires UploadPosts {
    if (!exists<UploadPosts>(account)) {
      return vector::empty<Post>()
    };
    let data = borrow_global<UploadPosts>(account);
    smart_vector::to_vector(&data.posts)
  }

  #[view]
  public fun is_following(account: address, person : address): bool acquires FollowData {
    let data = borrow_global<FollowData>(@social);
    if (!smart_table::contains(&data.following, account)) {
      return false;
    };
    let following = smart_table::borrow(&data.following, account);
    smart_vector::contains(following, &person)


  }

  #[view]
  public fun is_followed(account: address, person : address): bool acquires FollowData {
    let data = borrow_global<FollowData>(@social);
    if (!smart_table::contains(&data.followers, account)) {
      return false;
    };
    let followers = smart_table::borrow(&data.followers, account);
    smart_vector::contains(followers, &person)
  }

  #[test_only]
  public fun init_module_for_test(account_signer: &signer, user_account: address) acquires ProtocolManagedFA {
    init_module(account_signer);
    let protocol_fa_address = object::create_object_address(&signer::address_of(account_signer), b"social");
    primary_fungible_store::mint(&borrow_global<ProtocolManagedFA>(protocol_fa_address).mint_ref, user_account, 1_000_000_000);
  }

  #[test_only]
  public fun first_time_stake_native_for_test(account_signer: &signer, amount: u64, minimum_stake_config: u64, user_account: address) acquires ProtocolData, ProtocolConfig, ProtocolManagedFA, KOLManagedFa {
    first_time_stake_native(account_signer, string::utf8(b"0xHello"), amount, minimum_stake_config);
    let kol_fa_address = object::create_object_address(&signer::address_of(account_signer), b"social");
    primary_fungible_store::mint(&borrow_global<KOLManagedFa>(kol_fa_address).mint_ref, user_account, 1_000_000_000);
  }
}