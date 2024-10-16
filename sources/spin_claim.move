module aptos_spin_claim::spin_claim {
  use aptos_framework::fungible_asset::{Self, FungibleAsset, FungibleStore, Metadata};
  use aptos_framework::primary_fungible_store;
  use aptos_framework::object::{Self, Object, ExtendRef};
  use aptos_framework::bcs;

  use std::option::{Self, Option};
  use std::string::{Self, String};
  use std::signer;
  use std::vector;
  use std::ed25519;

  // List of errors
  const ENOT_ADMIN: u64 = 1;
  const ENOT_OPERATOR: u64 = 2;
  const ENOT_SUPPORTED: u64 = 3;
  const EINVALID_SIGNATURE: u64 = 4;
  const EOPERATOR_NOT_SET: u64 = 5;

  // ==================Events====================
  #[event]
  struct ClaimFAEvent has store, drop {
    sender: address,
    fa_obj: Object<Metadata>,
    amount: u64,
  }

  #[event]
  struct ClaimNFTEvent has store, drop {
    sender: address,
    // nft_obj: Object<Metadata>,
    // amount: u64,
  }

  // ==================Structs====================
  // /// Data regarding a fungible asset supported by the contract to be claimed
  // struct ClaimableAsset has store {
  //   total_claimed: SimpleMap<Object<Metadata>, u64>,
  // }

  // /// Data regarding the store object for a specific fungible asset
  // struct AssetStore has store {
  //   /// The fungible store for this token.
  //   store: Object<FungibleStore>,
  //   /// We need to keep the fungible store's extend ref to be able to transfer tokens from it during claiming.
  //   store_extend_ref: ExtendRef,
  // }

  /// Unique per FA
  // struct FAController has key {
  //   transfer_ref: fungible_asset::TransferRef,
  // }

  /// Data regarding all supported FA objects
  struct Registry has key {
    fa_objects: vector<Object<Metadata>>,
  }

  struct GlobalConfig has key {
    admin: address,
    operator_pk: Option<vector<u8>>,
  }

  struct ClaimData has copy, drop {
    beneficiary: address,
    fa_addr: address,
    index: u64,
    amount: u64,
  }

  /// If you deploy the module under an object, sender is the object's signer
  /// If you deploy the module under your own account, sender is your account's signer
  fun init_module(sender: &signer) {
    move_to(sender, Registry {
      fa_objects: vector::empty()
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
  ) acquires GlobalConfig, Registry {
    assert!(is_admin(sender), ENOT_ADMIN);

    let registry = borrow_global_mut<Registry>(@aptos_spin_claim);
    vector::push_back(
      &mut registry.fa_objects,
      fa_obj
    );
  }

  /// Remove a FA from the contract, admin only
  // public entry fun remove_fa(sender: &signer, fa_obj: Object<Metadata>) acquires Registry {
  //   assert!(is_admin(sender), ENOT_ADMIN);

  //   let registry = borrow_global_mut<Registry>(@aptos_spin_claim);
  //   let registry_fa_obj_addresses = &mut registry.fa_obj_addresses;
  //   let (is_exists, index) = vector::index_of(
  //     registry_fa_obj_addresses,
  //     object::object_address(&fa_obj)
  //   );
  //   assert!(is_exists, ENOT_SUPPORTED);
  //   vector::remove(registry_fa_obj_addresses, index);
  // }

  /// Withdraw FA from contract, admin only
  // public entry fun withdraw_fa(sender: &signer, fa_obj: Object<Metadata>) acquires Registry, FAController {
  //   let sender_addr = signer::address_of(sender);

  //   // TODO:
  // }

  // ============================================
  // User functions
  // ============================================

  /// Claim FA
  public entry fun claim_fa(
    sender: &signer,
    fa_obj: Object<Metadata>,
    index: u64,
    amount: u64,
    signature_bytes: vector<u8>,
  ) acquires GlobalConfig, Registry {
    let sender_addr = signer::address_of(sender);

    let config = borrow_global<GlobalConfig>(@aptos_spin_claim);
    let registry = borrow_global<Registry>(@aptos_spin_claim);
    let (is_exists, index) = vector::index_of(
      &registry.fa_objects,
      &fa_obj
    );
    assert!(is_exists, ENOT_SUPPORTED);

    if (option::is_some(&config.operator_pk)) {
      let message = ClaimData {
        beneficiary: sender_addr,
        fa_addr: object::object_address(&fa_obj),
        index,
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

      // transfer FA to sender
      let store_addr = primary_fungible_store::primary_store_address(sender_addr, fa_obj);
      let store = if (fungible_asset::store_exists(store_addr)) {
        object::address_to_object(store_addr)
      } else {
        primary_fungible_store::create_primary_store(sender_addr, fa_obj)
      };
      // transfer FA from spin claim store to sender store
      primary_fungible_store::transfer(sender, fa_obj, sender_addr, amount);
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
  public fun get_registry(): vector<Object<Metadata>> acquires Registry {
    let registry = borrow_global<Registry>(@aptos_spin_claim);
    registry.fa_objects
  }

  #[view]
  public fun create_claim_data(
    beneficiary: address,
    fa_addr: address,
    index: u64,
    amount: u64,
  ): ClaimData {
    ClaimData {
      beneficiary,
      fa_addr,
      index,
      amount,
    }
  }

  // #[view]
  // /// Get fungible asset metadata
  // public fun get_fa_objects_metadatas(
  //   collection_obj: Object<Metadata>
  // ): (String, String, u8) {
  //   let name = fungible_asset::name(collection_obj);
  //   let symbol = fungible_asset::symbol(collection_obj);
  //   let decimals = fungible_asset::decimals(collection_obj);
  //   (symbol, name, decimals)
  // }

  // ==================== Internal Functions ====================
  fun is_admin(sender: &signer): bool acquires GlobalConfig {
    let sender_address = signer::address_of(sender);
    let global_config = borrow_global<GlobalConfig>(@aptos_spin_claim);
    sender_address == global_config.admin
  }

  #[test_only]
  public fun initialize(sender: &signer) {
    init_module(sender);
  }
}
