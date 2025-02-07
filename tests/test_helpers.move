#[test_only]
module aptos_spin_claim::test_helpers {
  use aptos_framework::account;
  use aptos_framework::fungible_asset::{Self, FungibleAsset};
  use aptos_framework::object;
  use aptos_framework::primary_fungible_store;
  use aptos_framework::timestamp;
  use aptos_framework::coin::{Self, Coin, destroy_mint_cap, destroy_freeze_cap, destroy_burn_cap};

  use std::option;
  use std::string;
  use std::signer;
  use std::vector;

  public fun set_up() {
    timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@0x1));
  }

  public fun clean_up(assets: vector<FungibleAsset>) {
    vector::for_each(assets, |a| primary_fungible_store::deposit(@0x0, a));
  }

  public fun create_fungible_asset_and_mint(creator: &signer, name: vector<u8>, decimals: u8, amount: u64): FungibleAsset {
    let token_metadata = &object::create_named_object(creator, name);

    primary_fungible_store::create_primary_store_enabled_fungible_asset(
      token_metadata,
      option::none(),
      string::utf8(name),
      string::utf8(name),
      decimals,
      string::utf8(b""),
      string::utf8(b""),
    );

    let mint_ref = &fungible_asset::generate_mint_ref(token_metadata);
    fungible_asset::mint(mint_ref, amount)
  }

  public fun create_coin_and_mint<CoinType>(creator: &signer, name: vector<u8>, decimals: u8, amount: u64): Coin<CoinType> {
    let (burn_cap, freeze_cap, mint_cap) = coin::initialize<CoinType>(
      creator,
      string::utf8(name),
      string::utf8(name),
      decimals,
      true,
    );
    let coin = coin::mint<CoinType>(amount, &mint_cap);
    coin::destroy_burn_cap(burn_cap);
    coin::destroy_freeze_cap(freeze_cap);
    coin::destroy_mint_cap(mint_cap);
    coin
  }
}
