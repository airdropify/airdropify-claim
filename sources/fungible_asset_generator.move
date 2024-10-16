module aptos_spin_claim::fungible_asset_generator {
  use aptos_framework::fungible_asset;
  use aptos_framework::object;
  use aptos_framework::primary_fungible_store;
  use aptos_std::math128;
  use aptos_std::math64;

  use std::option::Self;
  use std::signer;
  use std::string::Self;

  struct FAController has key {
    mint_ref: fungible_asset::MintRef,
    burn_ref: fungible_asset::BurnRef,
    transfer_ref: fungible_asset::TransferRef
  }

  public entry fun create_fa(
    sender: &signer,
    max_supply: option::Option<u128>,
    name: string::String,
    symbol: string::String,
    decimals: u8,
    icon_uri: string::String,
    project_uri: string::String
  ) {
    let fa_obj_constructor_ref = &object::create_named_object(
      sender,
      *string::bytes(&name),
    );
    let fa_obj_signer = object::generate_signer(fa_obj_constructor_ref);
    let converted_max_supply = if (option::is_some(&max_supply)) {
      option::some(
        option::extract(&mut max_supply) * math128::pow(10, (decimals as u128))
      )
    } else {
      option::none()
    };
    primary_fungible_store::create_primary_store_enabled_fungible_asset(
      fa_obj_constructor_ref,
      converted_max_supply,
      name,
      symbol,
      decimals,
      icon_uri,
      project_uri
    );
    let mint_ref = fungible_asset::generate_mint_ref(fa_obj_constructor_ref);
    let burn_ref = fungible_asset::generate_burn_ref(fa_obj_constructor_ref);
    let transfer_ref = fungible_asset::generate_transfer_ref(fa_obj_constructor_ref);
    move_to(&fa_obj_signer, FAController {
      mint_ref,
      burn_ref,
      transfer_ref,
    });
  }

  public entry fun mint_fa(
    sender: &signer,
    fa: object::Object<fungible_asset::Metadata>,
    amount: u64,
  ) acquires FAController {
    let sender_addr = signer::address_of(sender);
    let fa_obj_addr = object::object_address(&fa);
    let config = borrow_global<FAController>(fa_obj_addr);
    let decimals = fungible_asset::decimals(fa);
    primary_fungible_store::mint(&config.mint_ref, sender_addr, amount * math64::pow(10, (decimals as u64)));
  }
}
