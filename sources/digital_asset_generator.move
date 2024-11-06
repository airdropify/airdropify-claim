module aptos_spin_claim::digital_asset_generator {
    use aptos_token_objects::collection;
    use aptos_token_objects::token;

    use std::option::{Self, Option};
    use std::signer;
    use std::string::Self;

  public entry fun create_fixed_maximum_supply_collection(
    sender: &signer,
    max_supply: u64,
    name: string::String,
    description: string::String,
    uri: string::String,
  ) {
    let royalty = option::none();

    let collection_constructor_ref = &collection::create_fixed_collection(
      sender,
      description,
      max_supply,
      name,
      royalty,
      uri,
    );

    // let mutator_ref = collection::get_mutator_ref(collection_constructor_ref);
  }

  public entry fun create_unlimited_supply_collection(
    sender: &signer,
    name: string::String,
    description: string::String,
    uri: string::String,
  ) {
    let royalty = option::none();

    let collection_constructor_ref = &collection::create_unlimited_collection(
      sender,
      description,
      name,
      royalty,
      uri,
    );

    // let mutator_ref = collection::get_mutator_ref(collection_constructor_ref);
  }

  // This makes it easy to find the address for the token if you know the token and Collection name,
  // but named Objects are not deletable. Trying to delete the a named token will only delete the data,
  // not the Object itself.
  // You can derive the address for named tokens by:
  //   - Concatenating the creator address, collection name and token name.
  //   - Doing a sha256 hash of that new string.
  public entry fun mint_named_token(
    creator: &signer,
    collection_name: string::String,
    description: string::String,
    token_name: string::String,
    uri: string::String,
  ) {
    let royalty = option::none();
    token::create_named_token(
      creator,
      collection_name,
      description,
      token_name,
      royalty,
      uri,
    );
  }

  // These create unnamed Objects (which are deletable) but still have a Token name.
  // Because the Object address is not deterministic, you must use an Indexer to find the address for them.
  // https://aptos.dev/en/build/indexer/aptos-hosted
  public entry fun mint_unnamed_token(
    creator: &signer,
    collection_name: string::String,
    description: string::String,
    token_name: string::String,
    uri: string::String,
  ) {
    let royalty = option::none();
    token::create(
        creator,
        collection_name,
        description,
        token_name,
        royalty,
        uri,
    );
  }
}
