module aptos_swap::helper {
    
    use std::type_info;
    use std::string;
    
    use aptos_std::comparator::Self;

    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    const ERR_COIN_TYPE_SAME: u64 = 200;

    public fun min(
        x:u64,
        y:u64
    ): u64 {
        if (x < y) return x else return y
    }

    public fun sqrt(
        x: u64,
        y: u64
    ): u64 {
        sqrt_128((x as u128) * (y as u128))
    }

    public fun sqrt_128(
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

    /// Add but allow overflow
    public fun overflow_add(a: u128, b: u128): u128 {
        let r = MAX_U128 - b;
        if (r < a) {
            return a - r - 1
        };
        r = MAX_U128 - a;
        if (r < b) {
            return b - r - 1
        };
        a + b
    }

    public fun compare<CoinX, CoinY>(): bool{
        let type_name_coin_x = type_info::type_name<CoinX>();
        let type_name_coin_y = type_info::type_name<CoinY>();
        assert!(type_name_coin_x != type_name_coin_y, ERR_COIN_TYPE_SAME);

        if (string::length(&type_name_coin_x) < string::length(&type_name_coin_y)) return true;
        if (string::length(&type_name_coin_x) > string::length(&type_name_coin_y)) return false;

        let struct_cmp = comparator::compare(&type_name_coin_x, &type_name_coin_y);
        comparator::is_smaller_than(&struct_cmp)
    }
} 
