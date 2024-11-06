#[test_only]
module aptos_spin_claim::spin_claim_tests {
  use aptos_framework::fungible_asset::{Self, FungibleAsset, FungibleStore};
  use aptos_framework::object::{Self, Object};
  use aptos_framework::primary_fungible_store;
  use aptos_std::simple_map;
  use aptos_framework::bcs;
  use aptos_token_objects::token;

  use std::option::Self;
  use std::signer;
  use std::vector;
  use std::string;
  use aptos_spin_claim::spin_claim;
  use aptos_spin_claim::test_helpers;
  use aptos_spin_claim::fungible_asset_generator;

  #[test_only]
  use aptos_framework::aptos_coin;
  #[test_only]
  use aptos_framework::coin;
  #[test_only]
  use aptos_framework::account;
  #[test_only]
  use std::debug;
  #[test_only]
  use std::ed25519;

  #[test(admin = @aptos_spin_claim, new_admin = @0xbeef)]
  fun test_admin(
    admin: &signer,
    new_admin: &signer,
  ) {
    test_helpers::set_up();
    spin_claim::initialize(admin);

    let (sk, vpk) = ed25519::generate_keys();
    let vpk_bytes = ed25519::validated_public_key_to_bytes(&vpk);
    let admin_addr = spin_claim::get_admin();
    assert!(admin_addr == signer::address_of(admin), 0);

    let operator_pk = spin_claim::get_operator_pk();
    assert!(operator_pk == option::none(), 0);

    let new_admin_addr = signer::address_of(new_admin);
    spin_claim::set_admin(admin, new_admin_addr);
    admin_addr = spin_claim::get_admin();
    assert!(admin_addr == new_admin_addr, 0);

    spin_claim::set_operator_pk(new_admin, vpk_bytes);
    assert!(spin_claim::get_operator_pk() == option::some(vpk_bytes), 0);
  }

  #[test(admin = @aptos_spin_claim, new_admin = @0xbeef)]
  #[expected_failure(abort_code = 1)]
  fun test_set_admin_fail(admin: &signer, new_admin: &signer) {
    test_helpers::set_up();
    spin_claim::initialize(admin);

    let new_admin_addr = signer::address_of(new_admin);
    spin_claim::set_admin(new_admin, new_admin_addr);
  }

  #[test(admin = @aptos_spin_claim, fake_admin = @0xbeef)]
  #[expected_failure(abort_code = 1)]
  fun test_set_operator_pk_fail(admin: &signer, fake_admin: &signer) {
    test_helpers::set_up();

    let (sk, vpk) = ed25519::generate_keys();
    let vpk_bytes = ed25519::validated_public_key_to_bytes(&vpk);
    spin_claim::initialize(admin);

    spin_claim::set_operator_pk(fake_admin, vpk_bytes);
  }

  #[test(admin = @aptos_spin_claim, new_admin = @0xbeef)]
  fun test_add_fa(admin: &signer, new_admin: &signer) {
    test_helpers::set_up();
    spin_claim::initialize(admin);

    let new_admin_addr = signer::address_of(new_admin);
    spin_claim::set_admin(admin, new_admin_addr);

    let api = test_helpers::create_fungible_asset_and_mint(new_admin, b"Airdropify", 8, 0);
    let api_obj = fungible_asset::asset_metadata(&api);

    spin_claim::add_fa(new_admin, api_obj);
    // dispose the api object
    fungible_asset::destroy_zero(api);
    assert!(spin_claim::get_registry() == vector[api_obj], 0);
  }

  #[test(admin = @aptos_spin_claim, new_admin = @0xbeef)]
  fun test_remove_fa(admin: &signer, new_admin: &signer) {
    test_helpers::set_up();
    spin_claim::initialize(admin);

    let new_admin_addr = signer::address_of(new_admin);
    spin_claim::set_admin(admin, new_admin_addr);

    let api = test_helpers::create_fungible_asset_and_mint(new_admin, b"Airdropify", 8, 0);
    let api_obj = fungible_asset::asset_metadata(&api);

    spin_claim::add_fa(new_admin, api_obj);
    // dispose the api object
    fungible_asset::destroy_zero(api);
    assert!(spin_claim::get_registry() == vector[api_obj], 0);

    spin_claim::remove_fa(new_admin, api_obj);
    assert!(spin_claim::get_registry() == vector[], 0);
  }

  #[test(module_signer = @aptos_spin_claim, admin = @0xbeef)]
  fun test_deposit_fa(module_signer: &signer, admin: &signer) {
    test_helpers::set_up();
    spin_claim::initialize(module_signer);

    let admin_addr = signer::address_of(admin);
    spin_claim::set_admin(module_signer, admin_addr);

    let api = test_helpers::create_fungible_asset_and_mint(admin, b"Airdropify", 8, 1_000_000);
    let api_obj = fungible_asset::asset_metadata(&api);

    // create a primary store
    let store_addr = primary_fungible_store::primary_store_address(admin_addr, api_obj);
    let store = if (fungible_asset::store_exists(store_addr)) {
      object::address_to_object(store_addr)
    } else {
      primary_fungible_store::create_primary_store(admin_addr, api_obj)
    };
    fungible_asset::deposit(store, api);
    let balance = fungible_asset::balance(store);
    assert!(balance == 1_000_000, 0);

    spin_claim::add_fa(admin, api_obj);

    // deposit the fa to the spin claim contract
    spin_claim::deposit_fa(admin, api_obj, 1_000_000);

    let balance = spin_claim::get_asset_store_balance(api_obj);
    assert!(balance == 1_000_000, 0);
  }

  #[test(module_signer = @aptos_spin_claim, admin = @0xbeef)]
  fun test_withdraw_fa(module_signer: &signer, admin: &signer) {
    test_helpers::set_up();
    spin_claim::initialize(module_signer);

    let admin_addr = signer::address_of(admin);
    spin_claim::set_admin(module_signer, admin_addr);

    let api = test_helpers::create_fungible_asset_and_mint(admin, b"Airdropify", 8, 1_000_000);
    let api_obj = fungible_asset::asset_metadata(&api);

    // create a primary store
    let store_addr = primary_fungible_store::primary_store_address(admin_addr, api_obj);
    let store = if (fungible_asset::store_exists(store_addr)) {
      object::address_to_object(store_addr)
    } else {
      primary_fungible_store::create_primary_store(admin_addr, api_obj)
    };
    fungible_asset::deposit(store, api);
    let balance = fungible_asset::balance(store);
    assert!(balance == 1_000_000, 0);

    spin_claim::add_fa(admin, api_obj);

    // deposit the fa to the spin claim contract
    spin_claim::deposit_fa(admin, api_obj, 1_000_000);

    let balance = spin_claim::get_asset_store_balance(api_obj);
    assert!(balance == 1_000_000, 0);
    let admin_balance = fungible_asset::balance(store);
    assert!(admin_balance == 0, 0);

    spin_claim::withdraw_fa(admin, api_obj, 1_000_000);

    let sc_balance = spin_claim::get_asset_store_balance(api_obj);
    assert!(sc_balance == 0, 0);
    let admin_balance = fungible_asset::balance(store);
    assert!(admin_balance == 1_000_000, 0);
  }

  #[test(module_signer = @aptos_spin_claim, admin = @0xbeef, user = @0xdead)]
  fun test_claim_fungible_asset(
    module_signer: &signer,
    admin: &signer,
    user: &signer,
  ) {
    test_helpers::set_up();
    spin_claim::initialize(module_signer);

    let admin_addr = signer::address_of(admin);
    spin_claim::set_admin(module_signer, admin_addr);

    let api = test_helpers::create_fungible_asset_and_mint(admin, b"Airdropify", 8, 1_000_000);
    let api_obj = fungible_asset::asset_metadata(&api);

    let (sk, vpk) = ed25519::generate_keys();
    let vpk_bytes = ed25519::validated_public_key_to_bytes(&vpk);

    spin_claim::set_operator_pk(admin, vpk_bytes);

    let store_addr = primary_fungible_store::primary_store_address(admin_addr, api_obj);
    let store = if (fungible_asset::store_exists(store_addr)) {
      object::address_to_object(store_addr)
    } else {
      primary_fungible_store::create_primary_store(admin_addr, api_obj)
    };
    fungible_asset::deposit(store, api);
    let balance = fungible_asset::balance(store);
    assert!(balance == 1_000_000, 0);

    spin_claim::add_fa(admin, api_obj);

    // deposit the fa to the spin claim contract
    spin_claim::deposit_fa(admin, api_obj, 1_000_000);

    let balance = spin_claim::get_asset_store_balance(api_obj);
    assert!(balance == 1_000_000, 0);

    let amount = 10;
    let index = 0;
    let user_addr = signer::address_of(user);
    let message = spin_claim::create_claim_fungible_asset_data(
      user_addr,
      object::object_address(&api_obj),
      index,
      amount,
    );
    let message_bytes = bcs::to_bytes(&message);

    let signature = ed25519::sign_arbitrary_bytes(&sk, message_bytes);
    let sig_bytes = ed25519::signature_to_bytes(&signature);

    spin_claim::claim_fa(
      user,
      api_obj,
      index,
      amount,
      sig_bytes,
    );

    let user_store_addr = primary_fungible_store::primary_store_address(user_addr, api_obj);
    let user_store = object::address_to_object<FungibleStore>(user_store_addr);
    let user_balance = fungible_asset::balance(user_store);
    assert!(user_balance == 10, 0);

    let claim_history_amount = spin_claim::get_claim_fungible_asset_history_amount(user_addr, api_obj, index);
    assert!(claim_history_amount == 10, 0);
  }

  #[test(module_signer = @aptos_spin_claim, admin = @0xbeef, user = @0xdead)]
  fun test_claim_digital_asset(
    module_signer: &signer,
    admin: &signer,
    user: &signer,
  ) {
    test_helpers::set_up();
    spin_claim::initialize(module_signer);

    let admin_addr = signer::address_of(admin);
    spin_claim::set_admin(module_signer, admin_addr);

    let collection_name = string::utf8(b"Octopus Collection");
    let description = string::utf8(b"Collection Description");
    let uri = string::utf8(b"https://octopus.com");
    let token_name = string::utf8(b"Octopus #1");

    spin_claim::create_collection(
      admin,
      collection_name,
      description,
      uri,
    );

    let (sk, vpk) = ed25519::generate_keys();
    let vpk_bytes = ed25519::validated_public_key_to_bytes(&vpk);

    spin_claim::set_operator_pk(admin, vpk_bytes);

    let user_addr = signer::address_of(user);
    let message = spin_claim::create_claim_digital_asset_data(
      user_addr,
      collection_name,
      description,
      token_name,
      uri,
    );
    let message_bytes = bcs::to_bytes(&message);

    let signature = ed25519::sign_arbitrary_bytes(&sk, message_bytes);
    let sig_bytes = ed25519::signature_to_bytes(&signature);

    spin_claim::claim_da(
      user,
      collection_name,
      description,
      token_name,
      uri,
      sig_bytes,
    );

    let token_addr = spin_claim::get_token_address(collection_name, token_name);
    let token = object::address_to_object<token::Token>(token_addr);
    assert!(object::owner(token) == user_addr, 1);
  }
}
