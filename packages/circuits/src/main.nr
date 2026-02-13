/// ShadowBid ZK Range Proof Circuit
///
/// Proves that a bid amount satisfies the auction constraints
/// WITHOUT revealing the actual bid amount.
///
/// Public inputs:
///   - min_price: The minimum acceptable bid
///   - commitment: The Pedersen hash commitment of the bid
///
/// Private inputs:
///   - bid_amount: The actual bid value (kept secret)
///   - salt: Random salt used in the commitment

/// Main circuit function - proves bid validity
fn main(
    bid_amount: Field,     // private: actual bid value
    salt: Field,           // private: random salt for commitment
    min_price: pub Field,  // public: auction minimum price
    max_price: pub Field,  // public: auction maximum price (sanity check)
    commitment: pub Field, // public: hash(bid_amount, salt)
) {
    // 1. Prove bid_amount >= min_price
    let bid_u64 = bid_amount as u64;
    let min_u64 = min_price as u64;
    assert(bid_u64 >= min_u64, "Bid must be >= min_price");

    // 2. Prove bid_amount <= max_price
    let max_u64 = max_price as u64;
    assert(bid_u64 <= max_u64, "Bid must be <= max_price");

    // 3. Verify commitment matches hash(bid_amount, salt)
    let computed_commitment = std::hash::pedersen_hash([bid_amount, salt]);
    assert(commitment == computed_commitment, "Commitment mismatch");
}

#[test]
fn test_valid_bid() {
    let bid = 100;
    let salt = 42;
    let min = 50;
    let max = 200;
    let commitment = std::hash::pedersen_hash([bid, salt]);
    main(bid, salt, min, max, commitment);
}

#[test(should_fail_with = "Bid must be <= max_price")]
fn test_bid_above_max() {
    let bid = 201;
    let salt = 42;
    let min = 50;
    let max = 200;
    let commitment = std::hash::pedersen_hash([bid, salt]);
    main(bid, salt, min, max, commitment);
}

#[test]
fn test_bid_at_minimum() {
    // A bid exactly at the minimum price
    let bid = 50;
    let salt = 123;
    let min = 50;
    let max = 200;
    let commitment = std::hash::pedersen_hash([bid, salt]);
    main(bid, salt, min, max, commitment);
}

#[test(should_fail_with = "Bid must be >= min_price")]
fn test_bid_below_minimum() {
    // A bid of 10 with min_price of 50 should fail
    let bid = 10;
    let salt = 42;
    let min = 50;
    let max = 200;
    let commitment = std::hash::pedersen_hash([bid, salt]);
    main(bid, salt, min, max, commitment);
}

#[test(should_fail_with = "Commitment mismatch")]
fn test_wrong_commitment() {
    // A bid of 100 with wrong commitment should fail
    let bid = 100;
    let salt = 42;
    let min = 50;
    let max = 200;
    let wrong_commitment = std::hash::pedersen_hash([bid, 999]); // wrong salt
    main(bid, salt, min, max, wrong_commitment);
}
