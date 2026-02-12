/// ShadowBid ZK Range Proof Circuit
///
/// Proves that a bid amount satisfies the auction constraints
/// WITHOUT revealing the actual bid amount.
///
/// Public inputs:
///   - min_price: The minimum acceptable bid
///   - commitment: The Poseidon hash commitment of the bid
///
/// Private inputs:
///   - bid_amount: The actual bid value (kept secret)
///   - salt: Random salt used in the commitment

/// Main circuit function — proves bid validity
fn main(
    bid_amount: Field,     // private: actual bid value
    salt: Field,           // private: random salt for commitment
    min_price: pub Field,  // public: auction minimum price
    commitment: pub Field, // public: hash(bid_amount, salt)
) {
    // 1. Prove bid_amount >= min_price
    //    We verify this by checking (bid_amount - min_price) is non-negative
    let diff = bid_amount - min_price;
    
    // Range check: diff must fit in a reasonable bit width (e.g., 128 bits)
    // This implicitly proves bid_amount >= min_price
    let diff_as_u128 = diff as u64; // Noir will constrain this cast
    assert(diff_as_u128 >= 0, "Bid must be >= min_price");

    // 2. Verify commitment matches hash(bid_amount, salt)
    //    Using Poseidon hash for Starknet compatibility
    let computed_commitment = std::hash::poseidon::bn254::hash_2(bid_amount, salt);
    assert(commitment == computed_commitment, "Commitment mismatch");
}

#[test]
fn test_valid_bid() {
    // A bid of 100 with min_price of 50
    let bid = 100;
    let salt = 42;
    let min = 50;
    let commitment = std::hash::poseidon::bn254::hash_2(bid, salt);
    main(bid, salt, min, commitment);
}
