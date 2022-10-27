/// Core module: implement core logic for swap pool

/// TODO: emit event, check pause, check fee on
module aptos_swap::core {
    
    use std::signer;
    use std::event;
    use std::string::{Self, String, utf8};
    use std::option::{Self};

    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, Coin, MintCapability, FreezeCapability, BurnCapability};
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::resource_account;

    use u256::u256;
    use uq64x64::uq64x64;

    use aptos_swap::helper;
    use aptos_swap::lp_coin::LPCoin;

    const MINIMUM_LIQUIDITY: u64 = 1000;

    const ERR_INSUFFICIENT_LIQUIDITY_MINT: u64 = 100;

    struct GlobalConfig has key {
        signer_cap: SignerCapability,
        admin_address: address,
        lp_fee: u64,
        protocol_fee: u64,
        is_global_pause: bool
    }

    struct Pool<phantom CoinX, phantom CoinY> has key {
        coin_x_reserve: Coin<CoinX>,
        coin_y_reserve: Coin<CoinY>,
        last_block_timestamp: u64,
        last_price_x_cumulative: u128,
        last_price_y_cumulative: u128,
        k_last: u128,
        is_local_pause: bool,
        lp_mint_cap: MintCapability<LPCoin<CoinX, CoinY>>,
        lp_freeze_cap: FreezeCapability<LPCoin<CoinX, CoinY>>,
        lp_burn_cap: BurnCapability<LPCoin<CoinX, CoinY>>,
    }

    fun get_resource_account_signer(): signer acquires GlobalConfig {
        let signer_cap = &borrow_global<GlobalConfig>(@aptos_swap).signer_cap;
        account::create_signer_with_capability(signer_cap)
    }

    /// Initialize this module: create a resource account, a collection, and a token data id
    fun init_module(resource_account: &signer) {
        let resource_signer_cap = resource_account::retrieve_resource_account_cap(resource_account, @0xc98);

        move_to(resource_account, GlobalConfig{
            signer_cap: resource_signer_cap,
            admin_address: signer::address_of(resource_account),
            lp_fee: 25, // 0.25%
            protocol_fee: 5, // 0.05%
            is_global_pause: false
        });
    }

    fun mint_coin<LPCoin> (account: &signer, amount: u64, mint_cap: &MintCapability<LPCoin>) {
        let acc_addr = signer::address_of(account);
        if (!coin::is_account_registered<LPCoin>(acc_addr)) {
            coin::register<LPCoin>(account);
        };
        let coins = coin::mint<LPCoin>(amount, mint_cap);
        coin::deposit(acc_addr, coins);
    }

    fun update_pool<CoinX, CoinY>(
        lp: &mut Pool<CoinX, CoinY>,
        balance_x: u64,
        balance_y: u64,
        reserve_x: u64,
        reserve_y: u64,
    ) {
        let now = timestamp::now_seconds();
        let time_elapsed = ((now - lp.last_block_timestamp) as u128);

        if (time_elapsed > 0 && reserve_x != 0 && reserve_y != 0) {
            let last_price_x_cumulative_delta = uq64x64::to_u128(uq64x64::fraction(reserve_y, reserve_x)) * time_elapsed;
            lp.last_price_x_cumulative = helper::overflow_add(lp.last_price_x_cumulative, last_price_x_cumulative_delta);

            let last_price_y_cumulative_delta = uq64x64::to_u128(uq64x64::fraction(reserve_x, reserve_y)) * time_elapsed;
            lp.last_price_y_cumulative = helper::overflow_add(lp.last_price_y_cumulative, last_price_y_cumulative_delta);
        };

        lp.last_block_timestamp = now;
        
        // TODO: emit event
    }

    /// mint function: call from other module
    public fun mint<CoinX, CoinY>(coin_x: Coin<CoinX>, coin_y: Coin<CoinY>): Coin<LPCoin<CoinX, CoinY>> acquires Pool, GlobalConfig {
        assert!(helper::compare<CoinX, CoinY>(), 101);
        
        let resource_account_signer = get_resource_account_signer();
        assert!(exists<Pool<CoinX, CoinY>>(signer::address_of(&resource_account_signer)), 102);

        let amount_x = coin::value(&coin_x);
        let amount_y = coin::value(&coin_y);
        
        let lp = borrow_global_mut<Pool<CoinX, CoinY>>(signer::address_of(&resource_account_signer));
        let (reserve_x, reserve_y) = (coin::value(&lp.coin_x_reserve), coin::value(&lp.coin_y_reserve));

        coin::merge(&mut lp.coin_x_reserve, coin_x);
        coin::merge(&mut lp.coin_y_reserve, coin_y);
        
        let (balance_x, balance_y) = (coin::value(&lp.coin_x_reserve), coin::value(&lp.coin_y_reserve));

        let total_supply = option::extract(&mut coin::supply<LPCoin<CoinX, CoinY>>());
        let liquidity;
        if (total_supply == 0) {
            liquidity = helper::sqrt(amount_x, amount_y) - MINIMUM_LIQUIDITY;
            mint_coin<LPCoin<CoinX, CoinY>>(&resource_account_signer, MINIMUM_LIQUIDITY, &lp.lp_mint_cap);
        } else {
            let amount_1 = ((amount_x as u128) * total_supply / (reserve_x as u128) as u64);
            let amount_2 = ((amount_y as u128) * total_supply / (reserve_y as u128) as u64);
            liquidity = helper::min(amount_1, amount_2)
        };

        assert!(liquidity > 0, ERR_INSUFFICIENT_LIQUIDITY_MINT);
        let coin = coin::mint<LPCoin<CoinX, CoinY>>(liquidity, &lp.lp_mint_cap);

        update_pool(lp, balance_x, balance_y, reserve_x, reserve_y);

        coin
    }

    /// burn function: call from other module
    public fun burn<CoinX, CoinY>(coin_liquidity: Coin<LPCoin<CoinX, CoinY>>): (Coin<CoinX>, Coin<CoinY>) acquires Pool, GlobalConfig {
        assert!(helper::compare<CoinX, CoinY>(), 101);
        
        let resource_account_signer = get_resource_account_signer();
        assert!(exists<Pool<CoinX, CoinY>>(signer::address_of(&resource_account_signer)), 102);

        let liquidity_amount = coin::value(&coin_liquidity);
        let lp = borrow_global_mut<Pool<CoinX, CoinY>>(signer::address_of(&resource_account_signer));
        let (reserve_x, reserve_y) = (coin::value(&lp.coin_x_reserve), coin::value(&lp.coin_y_reserve));

        let total_supply = option::extract(&mut coin::supply<LPCoin<CoinX, CoinY>>());

        let amount_x = ((liquidity_amount as u128) * (reserve_x as u128) / total_supply as u64);
        let amount_y = ((liquidity_amount as u128) * (reserve_y as u128) / total_supply as u64);
        
        let x_coin_to_return = coin::extract(&mut lp.coin_x_reserve, amount_x);
        let y_coin_to_return = coin::extract(&mut lp.coin_y_reserve, amount_y);

        assert!(amount_x > 0 && amount_y > 0, 103);

        let (balance_x, balance_y) = (coin::value(&lp.coin_x_reserve), coin::value(&lp.coin_y_reserve));
        coin::burn<LPCoin<CoinX, CoinY>>(coin_liquidity, &lp.lp_burn_cap);
        
        update_pool(lp, balance_x, balance_y, reserve_x, reserve_y);

        (x_coin_to_return, y_coin_to_return)
    }

    /// swap function
    public fun swap<CoinX, CoinY>(coin_x: Coin<CoinX>, coin_y: Coin<CoinY>, amount_x_out: u64, amount_y_out: u64): (Coin<CoinX>, Coin<CoinY>) acquires Pool, GlobalConfig {
        assert!(helper::compare<CoinX, CoinY>(), 101);
        
        let resource_account_signer = get_resource_account_signer();
        assert!(exists<Pool<CoinX, CoinY>>(signer::address_of(&resource_account_signer)), 102);

        let amount_x_in = coin::value(&coin_x);
        let amount_y_in = coin::value(&coin_y);
        assert!(amount_x_in > 0 || amount_y_in > 0, 104);

        let lp = borrow_global_mut<Pool<CoinX, CoinY>>(signer::address_of(&resource_account_signer));

        let (reserve_x, reserve_y) = (coin::value(&lp.coin_x_reserve), coin::value(&lp.coin_y_reserve));
        assert!(amount_x_out < reserve_x && amount_y_out < reserve_y, 105);

        coin::merge(&mut lp.coin_x_reserve, coin_x);
        coin::merge(&mut lp.coin_y_reserve, coin_y);

        let coin_x_out = coin::extract(&mut lp.coin_x_reserve, amount_x_out);
        let coin_y_out = coin::extract(&mut lp.coin_y_reserve, amount_y_out);

        let (balance_x, balance_y) = (coin::value(&lp.coin_x_reserve), coin::value(&lp.coin_y_reserve));

        let balance_x_adjusted = (balance_x as u128) * 1000 - (amount_x_in as u128) * (3 as u128);
        let balance_y_adjusted = (balance_y as u128) * 1000 - (amount_y_in as u128) * (3 as u128);

        assert!(balance_x_adjusted * balance_y_adjusted >= (reserve_x as u128) * (reserve_y as u128) * 1000000, 106);

        update_pool(lp, balance_x, balance_y, reserve_x, reserve_y);

        (coin_x_out, coin_y_out)
    }

    /**
     * Entry function
     */
    public entry fun create_pool<CoinX, CoinY>() acquires GlobalConfig {
        assert!(helper::compare<CoinX, CoinY>(), 101);
        let resource_account_signer = get_resource_account_signer();

        let (lp_b, lp_f, lp_m) = coin::initialize<LPCoin<CoinX, CoinY>>(&resource_account_signer, utf8(b"AptosSwapLPToken"), utf8(b"ASLPCoin"), 8, true);

        move_to(&resource_account_signer, Pool<CoinX, CoinY>{
            coin_x_reserve: coin::zero<CoinX>(),
            coin_y_reserve: coin::zero<CoinY>(),
            last_block_timestamp: 0,
            last_price_x_cumulative: 0,
            last_price_y_cumulative: 0,
            k_last: 0,
            lp_mint_cap: lp_m,
            lp_freeze_cap: lp_f,
            lp_burn_cap: lp_b,
            is_local_pause: false,
        });
    }
}
