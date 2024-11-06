module aptos_spin_claim::spin_claim {
  use aptos_framework::fungible_asset::{Self, FungibleAsset, FungibleStore, Metadata};
  use aptos_framework::primary_fungible_store;
  use aptos_framework::object::{Self, Object, ExtendRef};
  use aptos_framework::bcs;
  use aptos_token_objects::collection;
  use aptos_token_objects::token;

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
  const EINSUFFICIENT_FUND: u64 = 8;
  const ETOKEN_NAME_TOO_LONG: u64 = 9;

  const MAX_TOKEN_NAME_LENGTH: u64 = 128;
  const MAX_TOKEN_SEED_LENGTH: u64 = 128;
  const MAX_URI_LENGTH: u64 = 512;
  const MAX_DESCRIPTION_LENGTH: u64 = 2048;

  // ==================Events====================
  #[event]
  struct ClaimDigitalAssetEvent has store, drop {
    sender: address,
    collection_name: String,
    name: String,
    description: String,
    uri: String,
  }

  #[event]
  struct ClaimFungibleAssetEvent has store, drop {
    sender: address,
    fa_obj: Object<Metadata>,
    index: u64,
    amount: u64,
  }

  #[event]
  struct ClaimNativeEvent has store, drop {
    sender: address,
    index: u64,
    amount: u64,
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

  /// Generate signer to create laimNativeHistory object
  struct ClaimNativeHistoryController has key {
    extend_ref: ExtendRef,
  }

  /// Generate signer to create ClaimDigitalAssetHistory object
  struct ClaimDigitalAssetHistoryController has key {
    extend_ref: ExtendRef,
  }

  /// Generate signer to create ClaimFungibleAssetHistory object
  struct ClaimFungibleAssetHistoryController has key {
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

  /// Data regarding all supported DA objects
  struct DigitalAssetRegistry has key, store {
    collection_names: vector<String>
  }

  struct GlobalConfig has key {
    admin: address,
    operator_pk: Option<vector<u8>>,
    // `extend_ref` of the collection manager object. Used to obtain its signer.
    collection_manager_extend_ref: ExtendRef,
  }

  struct ClaimNativeData has copy, drop {
    user: address,
    index: u64,
    amount: u64,
  }

  struct ClaimDigitalAssetData has copy, drop {
    user: address,
    collection_name: String,
    description: String,
    name: String,
    uri: String,
  }

  struct ClaimFungibleAssetData has copy, drop {
    user: address,
    fa_addr: address,
    index: u64,
    amount: u64,
  }

  struct ClaimNativeHistory has key, copy, store, drop {
    user: address,
    index: u64,
    amount: u64,
    timestamp: u64,
  }

  struct ClaimDigitalAssetHistory has key, copy, store, drop {
    user: address,
    collection_name: String,
    name: String,
    timestamp: u64,
  }

  struct ClaimFungibleAssetHistory has key, copy, store, drop {
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
    move_to(sender, DigitalAssetRegistry {
      collection_names: vector::empty()
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

    let claim_native_history_constructor_ref = object::create_object(
      signer::address_of(sender)
    );
    let claim_native_history_extend_ref = object::generate_extend_ref(
      &claim_native_history_constructor_ref
    );
    move_to(sender, ClaimNativeHistoryController {
      extend_ref: claim_native_history_extend_ref,
    });

    let claim_digital_asset_history_constructor_ref = object::create_object(
      signer::address_of(sender)
    );
    let claim_digital_asset_history_extend_ref = object::generate_extend_ref(
      &claim_digital_asset_history_constructor_ref
    );
    move_to(sender, ClaimDigitalAssetHistoryController {
      extend_ref: claim_digital_asset_history_extend_ref,
    });

    let claim_fungible_asset_history_constructor_ref = object::create_object(
      signer::address_of(sender)
    );
    let claim_fungible_asset_history_extend_ref = object::generate_extend_ref(
      &claim_fungible_asset_history_constructor_ref
    );
    move_to(sender, ClaimFungibleAssetHistoryController {
      extend_ref: claim_fungible_asset_history_extend_ref,
    });

    let collection_manager_constructor_ref = object::create_object(
      signer::address_of(sender)
    );
    move_to(sender, GlobalConfig {
      admin: signer::address_of(sender),
      operator_pk: option::none(),
      collection_manager_extend_ref: object::generate_extend_ref(
        &collection_manager_constructor_ref,
      )
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
  public entry fun withdraw_fa(sender: &signer, fa_obj: Object<Metadata>, amount: u64) acquires GlobalConfig, FungibleStoreController, Asset, AssetController {
    assert!(is_admin(sender), ENOT_ADMIN);
    assert!(amount > 0, EINVALID_AMOUNT);
    let sender_addr = signer::address_of(sender);

    let admin_store_addr = primary_fungible_store::primary_store_address(sender_addr, fa_obj);
    let admin_store = if (fungible_asset::store_exists(admin_store_addr)) {
      object::address_to_object(admin_store_addr)
    } else {
      primary_fungible_store::create_primary_store(sender_addr, fa_obj)
    };

    let balance = get_asset_store_balance(fa_obj);
    assert!(amount <= balance, EINSUFFICIENT_FUND);

    let asset_signer = &generate_fungible_store_signer();
    let asset_store = get_asset_store(fa_obj);
    fungible_asset::transfer(
      asset_signer,
      asset_store,
      admin_store,
      amount
    );
  }

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

  /// Create a new collection supporting to claim, admin only
  public entry fun create_collection(
    sender: &signer,
    collection_name: String,
    description: String,
    uri: String,
  ) acquires GlobalConfig, DigitalAssetRegistry {
    assert!(is_admin(sender), ENOT_ADMIN);

    // Creates the collection with unlimited supply and without establishing any royalty configuration.
    collection::create_unlimited_collection(
      &collection_manager_signer(),
      description,
      collection_name,
      option::none(),
      uri,
    );

    let registry = borrow_global_mut<DigitalAssetRegistry>(@aptos_spin_claim);
    vector::push_back(
      &mut registry.collection_names,
      collection_name
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
  ) acquires GlobalConfig, Asset, AssetRegistry, AssetController, FungibleStoreController, ClaimFungibleAssetHistoryController {
    let sender_addr = signer::address_of(sender);

    let config = borrow_global<GlobalConfig>(@aptos_spin_claim);
    let registry = borrow_global<AssetRegistry>(@aptos_spin_claim);
    let (is_exists, index) = vector::index_of(
      &registry.fa_objects,
      &fa_obj
    );
    assert!(is_exists, ENOT_SUPPORTED);

    if (option::is_some(&config.operator_pk)) {
      let message = ClaimFungibleAssetData {
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
      let claim_history_signer = &generate_claim_fungible_asset_history_object_signer();
      let claim_history_object_addr = get_claim_fungible_asset_history_object_address(
        sender_addr,
        object::object_address(&fa_obj),
        claim_index,
      );
      if (object::object_exists<ClaimFungibleAssetHistory>(claim_history_object_addr)) {
        assert!(false, EALREADY_CLAIMED);
      };
      create_new_claim_fungible_asset_history_object(
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

      // Emit claim FA event
      let event = ClaimFungibleAssetEvent {
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

  /// Claim DA
  public entry fun claim_da(
    sender: &signer,
    collection_name: String,
    description: String,
    name: String,
    uri: String,
    signature_bytes: vector<u8>,
  ) acquires GlobalConfig, DigitalAssetRegistry {
    let sender_addr = signer::address_of(sender);

    let registry = borrow_global<DigitalAssetRegistry>(@aptos_spin_claim);
    let (is_exists, index)= vector::index_of(
      &registry.collection_names,
      &collection_name
    );
    assert!(is_exists, ENOT_SUPPORTED);
    let config = borrow_global<GlobalConfig>(@aptos_spin_claim);
    if (option::is_some(&config.operator_pk)) {
      let message = ClaimDigitalAssetData {
        user: sender_addr,
        collection_name,
        description,
        name,
        uri,
      };
      let message_bytes = bcs::to_bytes(&message);
      let signature = ed25519::new_signature_from_bytes(signature_bytes);

      let operator_pk = option::borrow(&config.operator_pk);
      let pk = ed25519::new_unvalidated_public_key_from_bytes(*operator_pk);
      assert!(
        ed25519::signature_verify_strict(
          &signature,
          &pk,
          message_bytes,
        ),
        EINVALID_SIGNATURE,
      );

      // Mint Collection Item
      // and get the constructor ref of the token. The constructor ref
      // is used to generate the refs of the token.
      let constructor_ref = token::create_named_token(
        &collection_manager_signer(),
        collection_name,
        description,
        name,
        option::none(),
        uri,
      );

      // Generate the object signer and the refs. The refs is used to manage the token.
      let object_signer = object::generate_signer(&constructor_ref);
      let extend_ref = object::generate_extend_ref(&constructor_ref);

      // Transfer the token to the claimer.
      let transfer_ref = object::generate_transfer_ref(&constructor_ref);
      let linear_transfer_ref = object::generate_linear_transfer_ref(&transfer_ref);
      object::transfer_with_ref(linear_transfer_ref, sender_addr);

      // Emit Claim DA Event
      let event = ClaimDigitalAssetEvent {
        sender: sender_addr,
        collection_name,
        name,
        description,
        uri,
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
  public fun create_claim_fungible_asset_data(
    user: address,
    fa_addr: address,
    index: u64,
    amount: u64,
  ): ClaimFungibleAssetData {
    ClaimFungibleAssetData {
      user,
      fa_addr,
      index,
      amount,
    }
  }

  #[view]
  public fun create_claim_digital_asset_data(
    user: address,
    collection_name: String,
    description: String,
    name: String,
    uri: String,
  ): ClaimDigitalAssetData {
    ClaimDigitalAssetData {
      user,
      collection_name,
      description,
      name,
      uri,
    }
  }

  #[view]
  public fun get_claim_fungible_asset_history_amount(
    user_addr: address,
    fa_obj: Object<Metadata>,
    index: u64,
  ): u64 acquires ClaimFungibleAssetHistory, ClaimFungibleAssetHistoryController {
    let claim_history_object_addr = get_claim_fungible_asset_history_object_address(user_addr, object::object_address(&fa_obj), index);
    borrow_global<ClaimFungibleAssetHistory>(claim_history_object_addr).amount
  }

  #[view]
  public fun get_token_address(
    collection_name: String,
    name: String
  ): address acquires GlobalConfig {
    token::create_token_address(&signer::address_of(&collection_manager_signer()), &collection_name, &name)
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

  /// Create new claim fungible asset history
  fun create_new_claim_fungible_asset_history_object(
    user_addr: address,
    fa_obj: Object<Metadata>,
    index: u64,
    amount: u64,
  ) acquires ClaimFungibleAssetHistoryController {
    let fa_addr = object::object_address(&fa_obj);
    let claim_history_object_constructor_ref = &object::create_named_object(
      &generate_claim_fungible_asset_history_object_signer(),
      construct_claim_fungible_asset_history_object_seed(user_addr, fa_addr, index)
    );
    move_to(&object::generate_signer(claim_history_object_constructor_ref), ClaimFungibleAssetHistory {
      user: user_addr,
      fa_obj,
      index,
      amount,
      timestamp: timestamp::now_seconds(),
    });
  }

  /// Generate signer to create claim_fungible_asset_history object
  fun generate_claim_fungible_asset_history_object_signer(): signer acquires ClaimFungibleAssetHistoryController {
    object::generate_signer_for_extending(&borrow_global<ClaimFungibleAssetHistoryController>(@aptos_spin_claim).extend_ref)
  }

  /// Construct claim_fungible_asset_history object seed
  fun construct_claim_fungible_asset_history_object_seed(user_addr: address, fa_addr: address, index: u64): vector<u8> {
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

  fun get_claim_fungible_asset_history_object_address(user_addr: address, fa_addr: address, index: u64): address acquires ClaimFungibleAssetHistoryController {
    object::create_object_address(
      &signer::address_of(&generate_claim_fungible_asset_history_object_signer()),
      construct_claim_fungible_asset_history_object_seed(user_addr, fa_addr, index)
    )
  }

  /// Return the signer of the collection manager objects.
  fun collection_manager_signer(): signer acquires GlobalConfig {
    let manager = borrow_global<GlobalConfig>(@aptos_spin_claim);
    object::generate_signer_for_extending(&manager.collection_manager_extend_ref)
  }

  #[test_only]
  public fun initialize(sender: &signer) {
    init_module(sender);
  }
}
