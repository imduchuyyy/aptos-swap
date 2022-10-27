// Core module: implement core logic for swap pool
module aptos_swap::core {
    
    use std::signer;
    use std::event;
    use std::string::{Self, String, utf8};
    use std::option::{Self};

    use aptos_framework::coin::{Self, Coin, MintCapability, FreezeCapability, BurnCapability};
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::resource_account;

    const MINIMUM_LIQUIDITY: u64 = 1000;

    /// ErrorCode
    const ERR_INSUFFICIENT_LIQUIDITY_MINT: u64 = 100;

    struct GlobalConfig has key {
        signer_cap: SignerCapability,
        admin_address: address,
        lp_fee: u64,
        protocol_fee: u64,
        ui_fee: u64,
        is_global_pause: bool
    }

    struct LPCoin<phantom CoinX, phantom CoinY> {}

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
            ui_fee: 5, // 0.05%
            is_global_pause: false
        });
    }

    fun update_pool<CoinX, CoinY>(
        lp: &mut LiquidityPool<X, Y>,
    ) {

    }

    fun mint_coin<LPCoin> (account: &signer, amount: u64, mint_cap: &MintCapability<LPCoin>) {
        let acc_addr = signer::address_of(account);
        if (!coin::is_account_registered<LPCoin>(acc_addr)) {
            coin::register<LPCoin>(account);
        };
        let coins = coin::mint<LPCoin>(amount, mint_cap);
        coin::deposit(acc_addr, coins);
    }

    fun min(
        x:u64,
        y:u64
    ): u64 {
        if (x < y) return x else return y
    }

    fun sqrt(
        x: u64,
        y: u64
    ): u64 {
        sqrt_128((x as u128) * (y as u128))
    }

    fun sqrt_128(
        y: u128
    ): u64 {
        if (y < 4) {
            if (y == 0) {
                0
            } else {
                1
            }
        } else {
            let z = y;
            let x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            };
            (z as u64)
        }
    }

    /// mint function: call from other module
    public fun mint<CoinX, CoinY>(coin_x: Coin<CoinX>, coin_y: Coin<CoinY>) acquires Pool, GlobalConfig {
        let resource_account_signer = get_resource_account_signer();

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
            liquidity = sqrt(amount_x, amount_y) - MINIMUM_LIQUIDITY;
            mint_coin<LPCoin<CoinX, CoinY>>(&resource_account_signer, MINIMUM_LIQUIDITY, &lp.lp_mint_cap);
        } else {
            let amount_1 = ((amount_x as u128) * total_supply / (reserve_x as u128) as u64);
            let amount_2 = ((amount_y as u128) * total_supply / (reserve_y as u128) as u64);
            liquidity = min(amount_1, amount_2);
        };

        assert!(liquidity > 0, ERR_INSUFFICIENT_LIQUIDITY_MINT);
        let coin = coin::mint<LPCoin<CoinX, CoinY>>(liquidity, &lp.lp_mint_cap);
    }

    /**
     * Entry function
     */
    public entry fun create_pool<CoinX, CoinY>() acquires GlobalConfig {
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
