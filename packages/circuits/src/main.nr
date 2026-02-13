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
    commitment: pub Field, // public: hash(bid_amount, salt)
) {
    // 1. Prove bid_amount >= min_price
    //    Cast to u64 to enforce range check (Noir constrains the cast)
    let bid_u64 = bid_amount as u64;
    let min_u64 = min_price as u64;
    assert(bid_u64 >= min_u64, "Bid must be >= min_price");

    // 2. Verify commitment matches hash(bid_amount, salt)
    //    Using Pedersen hash (available in Noir stdlib, compatible with Cairo)
    let computed_commitment = std::hash::pedersen_hash([bid_amount, salt]);
    assert(commitment == computed_commitment, "Commitment mismatch");
}

#[test]
fn test_valid_bid() {
    // A bid of 100 with min_price of 50
    let bid = 100;
    let salt = 42;
    let min = 50;
    let commitment = std::hash::pedersen_hash([bid, salt]);
    main(bid, salt, min, commitment);
}

#[test]
fn test_bid_at_minimum() {
    // A bid exactly at the minimum price
    let bid = 50;
    let salt = 123;
    let min = 50;
    let commitment = std::hash::pedersen_hash([bid, salt]);
    main(bid, salt, min, commitment);
}

#[test(should_fail_with = "Bid must be >= min_price")]
fn test_bid_below_minimum() {
    // A bid of 10 with min_price of 50 should fail
    let bid = 10;
    let salt = 42;
    let min = 50;
    let commitment = std::hash::pedersen_hash([bid, salt]);
    main(bid, salt, min, commitment);
}

#[test(should_fail_with = "Commitment mismatch")]
fn test_wrong_commitment() {
    // A bid of 100 with wrong commitment should fail
    let bid = 100;
    let salt = 42;
    let min = 50;
    let wrong_commitment = std::hash::pedersen_hash([bid, 999]); // wrong salt
    main(bid, salt, min, wrong_commitment);
}
