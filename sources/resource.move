module aptos_swap::resource {
    use std::signer;
    use aptos_framework::account::{Self, SignerCapability};

    struct CapabilityStorage has key { signer_cap: SignerCapability }

    const ERR_NOT_PERMISSIONS: u64 = 201;

    public entry fun initialize_lp_account(
        admin: &signer,
        lp_coin_metadata_serialized: vector<u8>,
        lp_coin_code: vector<u8>
    ) {
        assert!(signer::address_of(admin) == @aptos_swap, ERR_NOT_PERMISSIONS);

        let (lp_acc, signer_cap) =
            account::create_resource_account(admin, b"aptos_swap_seeds");
        aptos_framework::code::publish_package_txn(
            &lp_acc,
            lp_coin_metadata_serialized,
            vector[lp_coin_code]
        );
        move_to(admin, CapabilityStorage { signer_cap });
    }

    public fun retrieve_signer_cap(admin: &signer): SignerCapability acquires CapabilityStorage {
        assert!(signer::address_of(admin) == @aptos_swap, ERR_NOT_PERMISSIONS);
        let CapabilityStorage { signer_cap } =
            move_from<CapabilityStorage>(signer::address_of(admin));
        signer_cap
    }
}
