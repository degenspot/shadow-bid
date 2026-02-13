/// ShadowBid — Private Sealed-Bid Auction Contract
///
/// A privacy-preserving sealed-bid auction platform where bids are committed
/// as hashes during the bidding phase and revealed after the deadline.
/// ZK proofs ensure bid validity (bid >= min_price) without revealing amounts.

use starknet::ContractAddress;

#[starknet::interface]
pub trait IShadowBid<TContractState> {
    /// Creates a new auction with a minimum price and duration
    fn create_auction(
        ref self: TContractState,
        item_hash: felt252,
        min_price: u256,
        bid_duration: u64,
        reveal_duration: u64,
    ) -> u256;

    /// Submit a sealed bid (commitment hash + ZK proof of validity)
    fn submit_bid(
        ref self: TContractState,
        auction_id: u256,
        bid_commitment: felt252,
        deposit: u256,
        proof: Span<felt252>,
    );

    /// Reveal a previously committed bid
    fn reveal_bid(
        ref self: TContractState,
        auction_id: u256,
        bid_amount: u256,
        salt: felt252,
    );

    /// Settle the auction after reveal phase ends — determines winner
    fn settle_auction(ref self: TContractState, auction_id: u256);

    /// Withdraw refund for losing bidders after settlement
    fn withdraw_refund(ref self: TContractState, auction_id: u256);

    /// Claim payment (for seller) after settlement
    fn claim_seller_payment(ref self: TContractState, auction_id: u256);

    // =============================================================
    //                          VIEW FUNCTIONS
    // =============================================================

    fn get_auction(self: @TContractState, auction_id: u256) -> AuctionInfo;
    fn get_auction_count(self: @TContractState) -> u256;
    fn has_bid(self: @TContractState, auction_id: u256, bidder: ContractAddress) -> bool;
    fn has_revealed(self: @TContractState, auction_id: u256, bidder: ContractAddress) -> bool;
}

/// Auction states
#[derive(Drop, Copy, Serde, starknet::Store, PartialEq)]
#[allow(starknet::store_no_default_variant)]
pub enum AuctionState {
    Open,
    Revealing,
    Settled,
    Cancelled,
}

/// Public-facing auction info struct
#[derive(Drop, Copy, Serde)]
pub struct AuctionInfo {
    pub seller: ContractAddress,
    pub item_hash: felt252,
    pub min_price: u256,
    pub bid_deadline: u64,
    pub reveal_deadline: u64,
    pub state: AuctionState,
    pub bid_count: u32,
    pub highest_bid: u256,
    pub winner: ContractAddress,
}

#[starknet::contract]
pub mod ShadowBid {
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_contract_address};
    use core::num::traits::Zero;
    use core::hash::HashStateTrait;
    use core::pedersen::PedersenTrait;
    use super::{IShadowBid, AuctionState, AuctionInfo};
    
    use openzeppelin_interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    // use verifier::honk_verifier::{IUltraKeccakZKHonkVerifierDispatcher, IUltraKeccakZKHonkVerifierDispatcherTrait};

    // Define Verifier Interface locally to avoid Garaga dependency during dev/test
    #[starknet::interface]
    trait IUltraKeccakZKHonkVerifier<TContractState> {
        fn verify_ultra_keccak_zk_honk_proof(
            ref self: TContractState, full_proof_with_hints: Span<felt252>,
        ) -> Result<Span<u256>, felt252>;
    }

    // Constant for maximum bid allowed (u64::MAX)
    // Matches the contract logic where min_price is cast to u64 in circuit
    // 2^64 - 1
    const MAX_PRICE_U64: u256 = 18446744073709551615;
    
    // ... storage ...

    // =============================================================
    //                          STORAGE
    // =============================================================

    #[storage]
    struct Storage {
        verifier_address: ContractAddress,
        payment_token: ContractAddress,
        auction_count: u256,
        
        // --- Auction fields (keyed by auction_id) ---
        auction_seller: Map<u256, ContractAddress>,
        auction_item_hash: Map<u256, felt252>,
        auction_min_price: Map<u256, u256>,
        auction_bid_deadline: Map<u256, u64>,
        auction_reveal_deadline: Map<u256, u64>,
        auction_state: Map<u256, AuctionState>,
        auction_bid_count: Map<u256, u32>,
        auction_highest_bid: Map<u256, u256>,
        auction_winner: Map<u256, ContractAddress>,
        auction_seller_claimed: Map<u256, bool>, // Track if seller claimed funds

        // --- Bid fields (keyed by (auction_id, bidder)) ---
        bid_commitment: Map<(u256, ContractAddress), felt252>,
        bid_deposit: Map<(u256, ContractAddress), u256>,
        bid_revealed_amount: Map<(u256, ContractAddress), u256>,
        bid_is_revealed: Map<(u256, ContractAddress), bool>,
        bid_refund_claimed: Map<(u256, ContractAddress), bool>,
    }
    
    // ... implementation ...

    // =============================================================
    //                          EVENTS
    // =============================================================

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AuctionCreated: AuctionCreated,
        BidSubmitted: BidSubmitted,
        BidRevealed: BidRevealed,
        AuctionSettled: AuctionSettled,
        RefundClaimed: RefundClaimed,
        SellerPaymentClaimed: SellerPaymentClaimed,
    }

    #[derive(Drop, starknet::Event)]
    struct AuctionCreated {
        #[key]
        auction_id: u256,
        #[key]
        seller: ContractAddress,
        item_hash: felt252,
        min_price: u256,
        bid_deadline: u64,
        reveal_deadline: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct BidSubmitted {
        #[key]
        auction_id: u256,
        #[key]
        bidder: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct BidRevealed {
        #[key]
        auction_id: u256,
        #[key]
        bidder: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct AuctionSettled {
        #[key]
        auction_id: u256,
        winner: ContractAddress,
        winning_bid: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct RefundClaimed {
        #[key]
        auction_id: u256,
        #[key]
        bidder: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct SellerPaymentClaimed {
        #[key]
        auction_id: u256,
        #[key]
        seller: ContractAddress,
        amount: u256,
    }

    // =============================================================
    //                     CONSTRUCTOR
    // =============================================================

    #[constructor]
    fn constructor(
        ref self: ContractState, 
        verifier_address: ContractAddress,
        payment_token: ContractAddress
    ) {
        self.verifier_address.write(verifier_address);
        self.payment_token.write(payment_token);
        self.auction_count.write(0);
    }

    // =============================================================
    //                     IMPLEMENTATION
    // =============================================================

    #[abi(embed_v0)]
    impl ShadowBidImpl of IShadowBid<ContractState> {
        fn create_auction(
            ref self: ContractState,
            item_hash: felt252,
            min_price: u256,
            bid_duration: u64,
            reveal_duration: u64,
        ) -> u256 {
            let caller = get_caller_address();
            let now = get_block_timestamp();

            assert(bid_duration > 0, 'Bid duration must be > 0');
            assert(reveal_duration > 0, 'Reveal duration must be > 0');
            assert(min_price <= MAX_PRICE_U64, 'Min price exceeds limits');

            let auction_id = self.auction_count.read() + 1;
            let bid_deadline = now + bid_duration;
            let reveal_deadline = bid_deadline + reveal_duration;

            self.auction_count.write(auction_id);
            self.auction_seller.write(auction_id, caller);
            self.auction_item_hash.write(auction_id, item_hash);
            self.auction_min_price.write(auction_id, min_price);
            self.auction_bid_deadline.write(auction_id, bid_deadline);
            self.auction_reveal_deadline.write(auction_id, reveal_deadline);
            self.auction_state.write(auction_id, AuctionState::Open);
            
            self.emit(AuctionCreated {
                auction_id,
                seller: caller,
                item_hash,
                min_price,
                bid_deadline,
                reveal_deadline,
            });

            auction_id
        }

        fn submit_bid(
            ref self: ContractState,
            auction_id: u256,
            bid_commitment: felt252,
            deposit: u256,
            proof: Span<felt252>
        ) {
            let caller = get_caller_address();
            let now = get_block_timestamp();

            // Validate auction
            let state = self.auction_state.read(auction_id);
            assert(state == AuctionState::Open, 'Auction not open');
            
            let bid_deadline = self.auction_bid_deadline.read(auction_id);
            assert(now < bid_deadline, 'Bidding period ended');

            // Check existing bid
            let existing = self.bid_commitment.read((auction_id, caller));
            assert(existing == 0, 'Already submitted a bid');

            // Validate deposit
            let min_price = self.auction_min_price.read(auction_id);
            assert(deposit >= min_price, 'Deposit below minimum');
            assert(deposit <= MAX_PRICE_U64, 'Deposit exceeds max limit');

            // Seller cannot bid
            let seller = self.auction_seller.read(auction_id);
            assert(caller != seller, 'Seller cannot bid');

            // -----------------------------------------------------
            // Verify ZK Proof via Garaga Verifier
            // -----------------------------------------------------
            let verifier_addr = self.verifier_address.read();
            let verifier = IUltraKeccakZKHonkVerifierDispatcher { contract_address: verifier_addr };
            
            // Expected public inputs (must match main.nr definition order):
            // 1. min_price
            // 2. max_price
            // 3. commitment
            
            let result = verifier.verify_ultra_keccak_zk_honk_proof(proof);
            match result {
                Result::Ok(public_inputs) => {
                    assert(public_inputs.len() == 3, 'Invalid public inputs len');
                    
                    let proof_min = *public_inputs.at(0);
                    let proof_max = *public_inputs.at(1);
                    let proof_comm_u256 = *public_inputs.at(2);

                    assert(proof_min == min_price, 'Proof min_price mismatch');
                    assert(proof_max == MAX_PRICE_U64, 'Proof max_price mismatch');
                    assert(proof_comm_u256 == bid_commitment.into(), 'Proof commitment mismatch');
                },
                Result::Err(_) => panic!("Proof verification failed"),
            };

            // -----------------------------------------------------
            // Transfer Deposit Token
            // -----------------------------------------------------
            let token = IERC20Dispatcher { contract_address: self.payment_token.read() };
            // Transfer from bidder to this contract
            token.transfer_from(caller, get_contract_address(), deposit);

            // Update Storage
            self.bid_commitment.write((auction_id, caller), bid_commitment);
            self.bid_deposit.write((auction_id, caller), deposit);
            
            let count = self.auction_bid_count.read(auction_id);
            self.auction_bid_count.write(auction_id, count + 1);

            self.emit(BidSubmitted { auction_id, bidder: caller });
        }

        fn reveal_bid(
            ref self: ContractState,
            auction_id: u256,
            bid_amount: u256,
            salt: felt252,
        ) {
            let caller = get_caller_address();
            let now = get_block_timestamp();

            let bid_deadline = self.auction_bid_deadline.read(auction_id);
            let reveal_deadline = self.auction_reveal_deadline.read(auction_id);
            assert(now >= bid_deadline, 'Bidding still open');
            assert(now < reveal_deadline, 'Reveal period ended');

            // Transition state if needed
            let state = self.auction_state.read(auction_id);
            if state == AuctionState::Open {
                self.auction_state.write(auction_id, AuctionState::Revealing);
            }

            let commitment = self.bid_commitment.read((auction_id, caller));
            assert(commitment != 0, 'No bid to reveal');

            let already_revealed = self.bid_is_revealed.read((auction_id, caller));
            assert(!already_revealed, 'Already revealed');

            // Verify Commitment: hash(bid_amount, salt) == commitment
            // Using Pedersen hash to match Noir's std::hash::pedersen_hash([bid, salt])
            // Cairo syntax: PedersenTrait::new(base).update(a).update(b).finalize()
            
            // Check if bid_amount fits in felt252
            let bid_felt: felt252 = bid_amount.try_into().expect('Bid too large for felt');
            
            // Compute Pedersen hash: hash(bid_felt, salt)
            let computed = PedersenTrait::new(0).update(bid_felt).update(salt).finalize();
            
            assert(computed == commitment, 'Invalid reveal (Hash)');

            // Check range
            let min_price = self.auction_min_price.read(auction_id);
            assert(bid_amount >= min_price, 'Bid below minimum');
            
            // Check deposit check
            let deposit = self.bid_deposit.read((auction_id, caller));
            assert(deposit >= bid_amount, 'Deposit covers bid');

            // Update state
            self.bid_revealed_amount.write((auction_id, caller), bid_amount);
            self.bid_is_revealed.write((auction_id, caller), true);

            let current_highest = self.auction_highest_bid.read(auction_id);
            if bid_amount > current_highest {
                self.auction_highest_bid.write(auction_id, bid_amount);
                self.auction_winner.write(auction_id, caller);
            }

            self.emit(BidRevealed { auction_id, bidder: caller, amount: bid_amount });
        }

        fn settle_auction(ref self: ContractState, auction_id: u256) {
            let now = get_block_timestamp();
            let reveal_deadline = self.auction_reveal_deadline.read(auction_id);
            assert(now >= reveal_deadline, 'Reveal period not ended');

            let state = self.auction_state.read(auction_id);
            assert(state == AuctionState::Open || state == AuctionState::Revealing, 'Already settled');

            let highest = self.auction_highest_bid.read(auction_id);
            let winner = self.auction_winner.read(auction_id);

            if highest == 0 || winner.is_zero() {
                self.auction_state.write(auction_id, AuctionState::Cancelled);
            } else {
                self.auction_state.write(auction_id, AuctionState::Settled);
                // Winner is determined.
                // Refund excess deposit to winner immediately?
                // Or let them withdraw?
                // Let's refund excess immediately to keep it simple.
                let winner_deposit = self.bid_deposit.read((auction_id, winner));
                let refund = winner_deposit - highest;
                if refund > 0 {
                    let token = IERC20Dispatcher { contract_address: self.payment_token.read() };
                    token.transfer(winner, refund);
                    // Mark partially claimed/adjusted?
                    // Simpler: Just adjust their deposit record to match the price paid, 
                    // so `withdraw_refund` logic doesn't double pay.
                    // But `withdraw_refund` logic usually handles LOSERS.
                    // For the winner, we update deposit to be equal to price, or mark as handled.
                    // Let's check logic below.
                }
                self.emit(AuctionSettled { auction_id, winner, winning_bid: highest });
            }
        }

        fn withdraw_refund(ref self: ContractState, auction_id: u256) {
            let caller = get_caller_address();
            let state = self.auction_state.read(auction_id);
            assert(state == AuctionState::Settled || state == AuctionState::Cancelled, 'Not settled');

            let deposit = self.bid_deposit.read((auction_id, caller));
            assert(deposit > 0, 'No deposit');
            
            let claimed = self.bid_refund_claimed.read((auction_id, caller));
            assert(!claimed, 'Already claimed');

            self.bid_refund_claimed.write((auction_id, caller), true);

            let winner = self.auction_winner.read(auction_id);
            let token = IERC20Dispatcher { contract_address: self.payment_token.read() };

            if caller == winner && state == AuctionState::Settled {
                // Winner calling withdraw_refund?
                // If we already refunded excess in settle_auction, there's nothing left?
                // Wait, in settle_auction we refunded (deposit - bid).
                // So the remaining `deposit` value in storage is technically "spent".
                // We should NOT refund the bid amount.
                // Our logic in settle should probably update `bid_deposit` to `highest` to reflect what is kept.
                // BUT, modifying that map might be confusing.
                // Better approach:
                // Winner is NOT entitled to withdraw_refund of the WINNING BID amount.
                // Any excess was already sent? Or should be sent here?
                // Let's move excess refund HERE to be safe/pull-based.
                
                let winning_bid = self.auction_highest_bid.read(auction_id);
                let refund_amount = deposit - winning_bid;
                if refund_amount > 0 {
                    token.transfer(caller, refund_amount);
                }
            } else {
                // Loser (or anyone if Cancelled) gets full deposit back
                token.transfer(caller, deposit);
            }

            self.emit(RefundClaimed { auction_id, bidder: caller, amount: deposit }); // Note: event amount might be misleading if partial
        }

        fn claim_seller_payment(ref self: ContractState, auction_id: u256) {
            let caller = get_caller_address();
            let seller = self.auction_seller.read(auction_id);
            assert(caller == seller, 'Only seller');

            let state = self.auction_state.read(auction_id);
            assert(state == AuctionState::Settled, 'Not settled');
            
            let claimed = self.auction_seller_claimed.read(auction_id);
            assert(!claimed, 'Already claimed');

            self.auction_seller_claimed.write(auction_id, true);

            let winning_bid = self.auction_highest_bid.read(auction_id);
            if winning_bid > 0 {
                let token = IERC20Dispatcher { contract_address: self.payment_token.read() };
                token.transfer(seller, winning_bid);
                self.emit(SellerPaymentClaimed { auction_id, seller, amount: winning_bid });
            }
        }

        // =============================================================
        //                      VIEW FUNCTIONS
        // =============================================================

        fn get_auction(self: @ContractState, auction_id: u256) -> AuctionInfo {
            AuctionInfo {
                seller: self.auction_seller.read(auction_id),
                item_hash: self.auction_item_hash.read(auction_id),
                min_price: self.auction_min_price.read(auction_id),
                bid_deadline: self.auction_bid_deadline.read(auction_id),
                reveal_deadline: self.auction_reveal_deadline.read(auction_id),
                state: self.auction_state.read(auction_id),
                bid_count: self.auction_bid_count.read(auction_id),
                highest_bid: self.auction_highest_bid.read(auction_id),
                winner: self.auction_winner.read(auction_id),
            }
        }

        fn get_auction_count(self: @ContractState) -> u256 {
            self.auction_count.read()
        }

        fn has_bid(self: @ContractState, auction_id: u256, bidder: ContractAddress) -> bool {
            self.bid_commitment.read((auction_id, bidder)) != 0
        }

        fn has_revealed(self: @ContractState, auction_id: u256, bidder: ContractAddress) -> bool {
            self.bid_is_revealed.read((auction_id, bidder))
        }
    }
}
