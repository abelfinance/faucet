/// Basic faucet, allows to request coins between intervals.
module account::faucet {
    use std::signer;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, Coin};

    // Errors.

    /// When Faucet already exists on account.
    const ERR_FAUCET_EXISTS: u64 = 100;

    /// When Faucet doesn't exists on account.
    const ERR_FAUCET_NOT_EXISTS: u64 = 101;

    /// When user already got coins and currently restricted to request more funds.
    const ERR_RESTRICTED: u64 = 102;

    /// Faucet data.
    struct Faucet<phantom CoinType> has key {
        /// Faucet balance.
        deposit: Coin<CoinType>,
        /// How much coins should be sent to user per request.
        per_request: u64,
        /// Period between requests to faucet in seconds.
        period: u64,
    }

    /// If user has this resource on his account - he's not able to get more funds if (current_timestamp < since + period).
    struct Restricted<phantom Faucet> has key {
        since: u64,
    }

    // Public functions.

    /// Create a new faucet on `account` address.
    /// * `deposit` - initial coins on faucet balance.
    /// * `per_request` - how much funds should be distributed per user request.
    /// * `period` - interval allowed between requests for specific user.
    public fun create_faucet_internal<CoinType>(account: &signer, deposit: Coin<CoinType>, per_request: u64, period: u64) {
        let account_addr = signer::address_of(account);

        assert!(!exists<Faucet<CoinType>>(account_addr), ERR_FAUCET_EXISTS);

        move_to(account, Faucet<CoinType> {
            deposit,
            per_request,
            period
        });
    }

    /// Change settings of faucet `CoinType`.
    /// * `per_request` - how much funds should be distributed per user request.
    /// * `period` - interval allowed between requests for specific user.
    public fun change_settings_internal<CoinType>(account: &signer, per_request: u64, period: u64) acquires Faucet {
        let account_addr = signer::address_of(account);

        assert!(exists<Faucet<CoinType>>(account_addr), ERR_FAUCET_NOT_EXISTS);

        let faucet = borrow_global_mut<Faucet<CoinType>>(account_addr);
        faucet.per_request = per_request;
        faucet.period = period;
    }

    /// Deposist more coins `CoinType` to faucet.
    public fun deposit_internal<CoinType>(faucet_addr: address, deposit: Coin<CoinType>) acquires Faucet {
        assert!(exists<Faucet<CoinType>>(faucet_addr), ERR_FAUCET_NOT_EXISTS);

        let faucet = borrow_global_mut<Faucet<CoinType>>(faucet_addr);
        coin::merge(&mut faucet.deposit, deposit);
    }

    /// Requests coins `CoinType` from faucet `faucet_addr`.
    public fun request_internal<CoinType>(account: &signer, faucet_addr: address): Coin<CoinType> acquires Faucet, Restricted {
        let account_addr = signer::address_of(account);

        assert!(exists<Faucet<CoinType>>(faucet_addr), ERR_FAUCET_NOT_EXISTS);

        let faucet = borrow_global_mut<Faucet<CoinType>>(faucet_addr);
        let coins = coin::extract(&mut faucet.deposit, faucet.per_request);

        let now = timestamp::now_seconds();

        if (exists<Restricted<CoinType>>(account_addr)) {
            let restricted = borrow_global_mut<Restricted<CoinType>>(account_addr);
            assert!(restricted.since + faucet.period <= now, ERR_RESTRICTED);
            restricted.since = now;
        } else {
            move_to(account, Restricted<CoinType> {
                since: now,
            });
        };

        coins
    }

    // Scripts.

    /// Creates new faucet on `account` address for coin `CoinType`.
    /// * `account` - account which creates
    /// * `per_request` - how much funds should be distributed per user request.
    /// * `period` - interval allowed between requests for specific user.
    public entry fun create_faucet<CoinType>(account: &signer, amount_to_deposit: u64, per_request: u64, period: u64) {
        let coins = coin::withdraw<CoinType>(account, amount_to_deposit);

        create_faucet_internal(account, coins, per_request, period);
    }

    /// Changes faucet settings on `account`.
    public entry fun change_settings<CoinType>(account: &signer, per_request: u64, period: u64) acquires Faucet {
        change_settings_internal<CoinType>(account, per_request, period);
    }

    /// Deposits coins `CoinType` to faucet on `faucet` address, withdrawing funds from user balance.
    public entry fun deposit<CoinType>(account: &signer, faucet_addr: address, amount: u64) acquires Faucet {
        let coins = coin::withdraw<CoinType>(account, amount);

        deposit_internal<CoinType>(faucet_addr, coins);
    }

    /// Deposits coins `CoinType` from faucet on user's account.
    /// `faucet` - address of faucet to request funds.
    public entry fun request<CoinType>(account: &signer, faucet_addr: address) acquires Faucet, Restricted {
        let account_addr = signer::address_of(account);

        if (!coin::is_account_registered<CoinType>(account_addr)) {
            coin::register<CoinType>(account);
        };

        let coins = request_internal<CoinType>(account, faucet_addr);

        coin::deposit(account_addr, coins);
    }

}