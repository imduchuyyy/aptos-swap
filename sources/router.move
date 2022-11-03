module aptos_swap::router {
    use std::signer;
    use std::event;

    use aptos_swap::core::{Self, Pool, GlobalConfig};
    use aptos_swap::helper;

    public entry fun add_liquidity<CoinX, CoinY>(account: &signer, amount_x_desired: u64, amount_y_desired: u64, amount_x_min: u64, amount_y_min: u64) {
        let is_existed_pool = false;
        if (core::is_existed_pool<CoinX, CoinY>()) {
            is_existed_pool = true;
        };
        if (helper::compare<CoinX, CoinY>()) {
            if (!is_existed_pool) {
                core::create_pool<CoinX, CoinY>();
            };
        } else {

        };
    }

    public entry fun remove_liquidity<CoinX, CoinY>() {
    }

    public entry fun swap_exact_amount_in_one_route<CoinX, CoinY>() {
    }

    public entry fun swap_exact_amount_in_two_route<CoinX, CoinY, CoinZ>() {
    }

    public entry fun swap_exact_amount_in_three_route<CoinX, CoinY, CoinZ, CoinW>() {
    }
}
