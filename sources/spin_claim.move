module aptos_spin_claim::spin_claim {
  use aptos_framework::fungible_asset::{Self, FungibleAsset, FungibleStore, Metadata};
  use aptos_framework::primary_fungible_store;
  use aptos_framework::object::{Self, Object, ExtendRef};
  use aptos_framework::bcs;

  use aptos_std::string_utils;

  use std::option::{Self, Option};
  use std::string::{Self, String};
  use std::signer;
  use std::vector;
  use std::ed25519;
  use std::timestamp;

  // List of errors
  const ENOT_ADMIN: u64 = 1;
  const ENOT_OPERATOR: u64 = 2;
  const ENOT_SUPPORTED: u64 = 3;
  const EINVALID_SIGNATURE: u64 = 4;
  const EOPERATOR_NOT_SET: u64 = 5;
  const EINVALID_AMOUNT: u64 = 6;
  const EALREADY_CLAIMED: u64 = 7;

  // ==================Events====================
  #[event]
  struct ClaimFAEvent has store, drop {
    sender: address,
    fa_obj: Object<Metadata>,
    index: u64,
    amount: u64,
  }

  #[event]
  struct ClaimNFTEvent has store, drop {
    sender: address,
    // nft_obj: Object<Metadata>,
    // amount: u64,
  }

  // ==================Structs====================
  /// Generate signer to send FA from contract to user
  struct FungibleStoreController has key {
    extend_ref: ExtendRef,
  }

  /// Generate signer to create Asset object
  struct AssetController has key {
    extend_ref: ExtendRef,
  }

  /// Generate signer to create ClaimHistory object
  struct ClaimHistoryController has key {
    extend_ref: ExtendRef,
  }

  /// Data regarding all supported FA objects
  struct AssetRegistry has key, store {
    fa_objects: vector<Object<Metadata>>,
  }

  /// Unique per FA
  struct Asset has key, store, drop {
    // Fungible store to hold FA
    store: Object<FungibleStore>,
    // Total claimed amount
    total_claimed: u64,
  }

  struct GlobalConfig has key {
    admin: address,
    operator_pk: Option<vector<u8>>,
  }

  struct ClaimData has copy, drop {
    user: address,
    fa_addr: address,
    index: u64,
    amount: u64,
  }

  struct ClaimHistory has key, copy, store, drop {
    user: address,
    fa_obj: Object<Metadata>,
    index: u64,
    amount: u64,
    timestamp: u64,
  }

  /// If you deploy the module under an object, sender is the object's signer
  /// If you deploy the module under your own account, sender is your account's signer
  fun init_module(sender: &signer) {
    move_to(sender, AssetRegistry {
      fa_objects: vector::empty()
    });

    let asset_controller_constructor_ref = object::create_object(
      signer::address_of(sender)
    );
    let controller_extend_ref = object::generate_extend_ref(
      &asset_controller_constructor_ref
    );
    move_to(sender, AssetController {
      extend_ref: controller_extend_ref,
    });

    let fungible_store_constructor_ref = object::create_object(
      signer::address_of(sender)
    );
    let fungible_store_extend_ref = object::generate_extend_ref(
      &fungible_store_constructor_ref
    );
    move_to(sender, FungibleStoreController {
      extend_ref: fungible_store_extend_ref,
    });

    let claim_history_constructor_ref = object::create_object(
      signer::address_of(sender)
    );
    let claim_history_extend_ref = object::generate_extend_ref(
      &claim_history_constructor_ref
    );
    move_to(sender, ClaimHistoryController {
      extend_ref: claim_history_extend_ref,
    });

    move_to(sender, GlobalConfig {
      admin: signer::address_of(sender),
      operator_pk: option::none(),
    });
  }

  // ============================================
  // Admin functions
  // ============================================
  /// Transfer admin to new address
  public entry fun set_admin(sender: &signer, new_admin: address) acquires GlobalConfig {
    assert!(is_admin(sender), ENOT_ADMIN);
    let config = borrow_global_mut<GlobalConfig>(@aptos_spin_claim);
    config.admin = new_admin;
  }

  /// Set operator of the contract, admin only
  public entry fun set_operator_pk(sender: &signer, new_operator_pk: vector<u8>) acquires GlobalConfig {
    assert!(is_admin(sender), ENOT_ADMIN);
    let config = borrow_global_mut<GlobalConfig>(@aptos_spin_claim);
    config.operator_pk = option::some(new_operator_pk);
  }

  /// Add a FA to the contract, admin only
  public entry fun add_fa(
    sender: &signer,
    fa_obj: Object<Metadata>,
  ) acquires GlobalConfig, AssetRegistry, FungibleStoreController, AssetController {
    assert!(is_admin(sender), ENOT_ADMIN);

    let registry = borrow_global_mut<AssetRegistry>(@aptos_spin_claim);
    vector::push_back(
      &mut registry.fa_objects,
      fa_obj
    );

    let store_signer = &generate_fungible_store_signer();
    let asset_store_object_constructor_ref = &object::create_object(signer::address_of(store_signer));
    let asset_store = fungible_asset::create_store(
      asset_store_object_constructor_ref,
      fa_obj,
    );

    create_new_asset_object(fa_obj, asset_store);
  }

  /// Remove a FA from the contract, admin only
  public entry fun remove_fa(sender: &signer, fa_obj: Object<Metadata>) acquires GlobalConfig, AssetRegistry {
    assert!(is_admin(sender), ENOT_ADMIN);

    let registry = borrow_global_mut<AssetRegistry>(@aptos_spin_claim);
    let registry_fa_objects = &mut registry.fa_objects;
    let (is_exists, index) = vector::index_of(
      registry_fa_objects,
      &fa_obj
    );
    assert!(is_exists, ENOT_SUPPORTED);
    vector::remove(registry_fa_objects, index);
  }

  /// Withdraw FA from contract, admin only
  // public entry fun withdraw_fa(sender: &signer, fa_obj: Object<Metadata>) acquires Registry, FAController {
  //   let sender_addr = signer::address_of(sender);

  //   // TODO:
  // }

  /// Deposit FA to contract, admin only
  public entry fun deposit_fa(
    sender: &signer,
    fa_obj: Object<Metadata>,
    amount: u64
  ) acquires GlobalConfig, Asset, AssetRegistry, AssetController {
    assert!(is_admin(sender), ENOT_ADMIN);
    assert!(amount > 0, EINVALID_AMOUNT);

    // check if the FA is supported
    let registry = borrow_global<AssetRegistry>(@aptos_spin_claim);
    let (is_exists, index) = vector::index_of(
      &registry.fa_objects,
      &fa_obj
    );
    assert!(is_exists, ENOT_SUPPORTED);

    // get or create store for the aptos_spin_claim contract
    let asset_store = get_asset_store(fa_obj);

    let sender_addr = signer::address_of(sender);
    fungible_asset::transfer(
      sender,
      primary_fungible_store::primary_store(sender_addr, fa_obj),
      asset_store,
      amount
    );
  }

  // ============================================
  // User functions
  // ============================================
  /// Claim FA
  public entry fun claim_fa(
    sender: &signer,
    fa_obj: Object<Metadata>,
    claim_index: u64,
    amount: u64,
    signature_bytes: vector<u8>,
  ) acquires GlobalConfig, Asset, AssetRegistry, AssetController, FungibleStoreController, ClaimHistoryController {
    let sender_addr = signer::address_of(sender);

    let config = borrow_global<GlobalConfig>(@aptos_spin_claim);
    let registry = borrow_global<AssetRegistry>(@aptos_spin_claim);
    let (is_exists, index) = vector::index_of(
      &registry.fa_objects,
      &fa_obj
    );
    assert!(is_exists, ENOT_SUPPORTED);

    if (option::is_some(&config.operator_pk)) {
      let message = ClaimData {
        user: sender_addr,
        fa_addr: object::object_address(&fa_obj),
        index: claim_index,
        amount,
      };
      let message_bytes = bcs::to_bytes(&message);
      let signature = ed25519::new_signature_from_bytes(signature_bytes);

      let operator_pk = option::borrow(&config.operator_pk);
      let pk = ed25519::new_unvalidated_public_key_from_bytes(*operator_pk);
      assert!(
        ed25519::signature_verify_strict(
          &signature,
          &pk,
          message_bytes
        ),
        EINVALID_SIGNATURE
      );

      // Increase claimed amount
      let asset_object_addr = get_asset_object_address(object::object_address(&fa_obj));
      let asset = borrow_global_mut<Asset>(asset_object_addr);
      asset.total_claimed = asset.total_claimed + amount;

      // Mark as claimed
      // get or create claim history object
      let claim_history_signer = &generate_claim_history_object_signer();
      let claim_history_object_addr = get_claim_history_object_address(
        sender_addr,
        object::object_address(&fa_obj),
        claim_index,
      );
      if (object::object_exists<ClaimHistory>(claim_history_object_addr)) {
        assert!(false, EALREADY_CLAIMED);
      };
      create_new_claim_history_object(
        sender_addr,
        fa_obj,
        claim_index,
        amount,
      );

      // Create or get user store
      let user_store_addr = primary_fungible_store::primary_store_address(sender_addr, fa_obj);
      let user_store = if (fungible_asset::store_exists(user_store_addr)) {
        object::address_to_object(user_store_addr)
      } else {
        primary_fungible_store::create_primary_store(sender_addr, fa_obj)
      };

      // Transfer FA to user
      let asset_signer = &generate_fungible_store_signer();
      let asset_store = get_asset_store(fa_obj);
      fungible_asset::transfer(
        asset_signer,
        asset_store,
        user_store,
        amount
      );

      // Emit claim event
      let event = ClaimFAEvent {
        sender: sender_addr,
        fa_obj,
        index: claim_index,
        amount,
      };
      0x1::event::emit(event);
    } else {
      assert!(false, EOPERATOR_NOT_SET);
    }
  }

  // ============================================
  // View functions
  // ============================================
  #[view]
  /// Get contract admin
  public fun get_admin(): address acquires GlobalConfig {
    let config = borrow_global<GlobalConfig>(@aptos_spin_claim);
    config.admin
  }

  #[view]
  /// Get contract operator public key
  public fun get_operator_pk(): Option<vector<u8>> acquires GlobalConfig {
    let config = borrow_global<GlobalConfig>(@aptos_spin_claim);
    config.operator_pk
  }

  #[view]
  /// Get all fungible assets
  public fun get_registry(): vector<Object<Metadata>> acquires AssetRegistry {
    let registry = borrow_global<AssetRegistry>(@aptos_spin_claim);
    registry.fa_objects
  }

  #[view]
  /// Get asset object store balance
  public fun get_asset_store_balance(
    fa_obj: Object<Metadata>
  ): u64 acquires Asset, AssetController {
    let asset_object_addr = get_asset_object_address(object::object_address(&fa_obj));
    let asset = borrow_global<Asset>(asset_object_addr);
    fungible_asset::balance(asset.store)
  }

  #[view]
  public fun create_claim_data(
    user: address,
    fa_addr: address,
    index: u64,
    amount: u64,
  ): ClaimData {
    ClaimData {
      user,
      fa_addr,
      index,
      amount,
    }
  }

  #[view]
  public fun get_claim_history_amount(
    user_addr: address,
    fa_obj: Object<Metadata>,
    index: u64,
  ): u64 acquires ClaimHistory, ClaimHistoryController {
    let claim_history_object_addr = get_claim_history_object_address(user_addr, object::object_address(&fa_obj), index);
    borrow_global<ClaimHistory>(claim_history_object_addr).amount
  }

  // ==================== Internal Functions ====================
  fun is_admin(sender: &signer): bool acquires GlobalConfig {
    let sender_address = signer::address_of(sender);
    let global_config = borrow_global<GlobalConfig>(@aptos_spin_claim);
    sender_address == global_config.admin
  }

  /// Get store for a FA
  fun get_asset_store(
    fa_obj: Object<Metadata>,
  ): (Object<FungibleStore>) acquires Asset, AssetController {
    let fa_addr = object::object_address(&fa_obj);
    let asset_object_addr = get_asset_object_address(fa_addr);

    let asset = borrow_global<Asset>(asset_object_addr);
    asset.store
  }

  /// Create new asset entry with default values
  fun create_new_asset_object(
    fa_obj: Object<Metadata>,
    store: Object<FungibleStore>,
  ) acquires AssetController {
    let fa_addr = object::object_address(&fa_obj);
    let asset_object_constructor_ref = &object::create_named_object(
      &generate_asset_object_signer(),
      construct_asset_object_seed(fa_addr)
    );
    move_to(&object::generate_signer(asset_object_constructor_ref), Asset {
      store,
      total_claimed: 0,
    });
  }

  /// Generate signer to send FA from contract to user
  fun generate_fungible_store_signer(): signer acquires FungibleStoreController {
    object::generate_signer_for_extending(&borrow_global<FungibleStoreController>(@aptos_spin_claim).extend_ref)
  }

  /// Generate signer to create asset object
  fun generate_asset_object_signer(): signer acquires AssetController {
    object::generate_signer_for_extending(&borrow_global<AssetController>(@aptos_spin_claim).extend_ref)
  }

  /// Construct asset object seed
  fun construct_asset_object_seed(fa_addr: address): vector<u8> {
    bcs::to_bytes(&string_utils::format2(&b"{}_asset_{}", @aptos_spin_claim, fa_addr))
  }

  fun get_asset_object_address(fa_addr: address): address acquires AssetController {
    object::create_object_address(
      &signer::address_of(&generate_asset_object_signer()),
      construct_asset_object_seed(fa_addr)
    )
  }

  /// Create new claim history
  fun create_new_claim_history_object(
    user_addr: address,
    fa_obj: Object<Metadata>,
    index: u64,
    amount: u64,
  ) acquires ClaimHistoryController {
    let fa_addr = object::object_address(&fa_obj);
    let claim_history_object_constructor_ref = &object::create_named_object(
      &generate_claim_history_object_signer(),
      construct_claim_history_object_seed(user_addr, fa_addr, index)
    );
    move_to(&object::generate_signer(claim_history_object_constructor_ref), ClaimHistory {
      user: user_addr,
      fa_obj,
      index,
      amount,
      timestamp: timestamp::now_seconds(),
    });
  }

  /// Generate signer to create claim_history object
  fun generate_claim_history_object_signer(): signer acquires ClaimHistoryController {
    object::generate_signer_for_extending(&borrow_global<ClaimHistoryController>(@aptos_spin_claim).extend_ref)
  }

  /// Construct claim_history object seed
  fun construct_claim_history_object_seed(user_addr: address, fa_addr: address, index: u64): vector<u8> {
    bcs::to_bytes(
      &string_utils::format4(
        &b"{}_claimed_{}_{}_{}",
        @aptos_spin_claim,
        user_addr,
        fa_addr,
        index
      )
    )
  }

  fun get_claim_history_object_address(user_addr: address, fa_addr: address, index: u64): address acquires ClaimHistoryController {
    object::create_object_address(
      &signer::address_of(&generate_claim_history_object_signer()),
      construct_claim_history_object_seed(user_addr, fa_addr, index)
    )
  }

  #[test_only]
  public fun initialize(sender: &signer) {
    init_module(sender);
  }
}
