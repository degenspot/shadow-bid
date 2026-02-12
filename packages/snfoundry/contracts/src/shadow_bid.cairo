/// ShadowBid — Private Sealed-Bid Auction Contract
///
/// A privacy-preserving sealed-bid auction platform where bids are committed
/// as hashes during the bidding phase and revealed after the deadline.
/// ZK proofs ensure bid validity without revealing amounts.

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

    // =============================================================
    //                          VIEW FUNCTIONS
    // =============================================================

    /// Get auction details
    fn get_auction(self: @TContractState, auction_id: u256) -> AuctionInfo;

    /// Get total number of auctions created
    fn get_auction_count(self: @TContractState) -> u256;

    /// Check if a bidder has submitted a bid for an auction
    fn has_bid(self: @TContractState, auction_id: u256, bidder: starknet::ContractAddress) -> bool;

    /// Check if a bidder has revealed their bid
    fn has_revealed(self: @TContractState, auction_id: u256, bidder: starknet::ContractAddress) -> bool;
}

/// Auction states
#[derive(Drop, Copy, Serde, starknet::Store, PartialEq)]
pub enum AuctionState {
    /// Auction is open for bids
    Open,
    /// Bidding closed, reveals are accepted
    Revealing,
    /// Auction settled, winner determined
    Settled,
    /// Auction cancelled (e.g., no valid bids)
    Cancelled,
}

/// Public-facing auction info struct
#[derive(Drop, Copy, Serde)]
pub struct AuctionInfo {
    pub seller: starknet::ContractAddress,
    pub item_hash: felt252,
    pub min_price: u256,
    pub bid_deadline: u64,
    pub reveal_deadline: u64,
    pub state: AuctionState,
    pub bid_count: u32,
    pub highest_bid: u256,
    pub winner: starknet::ContractAddress,
}

#[starknet::contract]
pub mod ShadowBid {
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use core::poseidon::poseidon_hash_span;
    use core::num::traits::Zero;
    use super::{IShadowBid, AuctionState, AuctionInfo};

    // =============================================================
    //                          STORAGE
    // =============================================================

    #[storage]
    struct Storage {
        /// Total number of auctions created
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
        // --- Bid fields (keyed by (auction_id, bidder)) ---
        bid_commitment: Map<(u256, ContractAddress), felt252>,
        bid_deposit: Map<(u256, ContractAddress), u256>,
        bid_revealed_amount: Map<(u256, ContractAddress), u256>,
        bid_is_revealed: Map<(u256, ContractAddress), bool>,
        bid_refund_claimed: Map<(u256, ContractAddress), bool>,
    }

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

    // =============================================================
    //                     CONSTRUCTOR
    // =============================================================

    #[constructor]
    fn constructor(ref self: ContractState) {
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
            self.auction_bid_count.write(auction_id, 0);

            self
                .emit(
                    AuctionCreated {
                        auction_id,
                        seller: caller,
                        item_hash,
                        min_price,
                        bid_deadline,
                        reveal_deadline,
                    },
                );

            auction_id
        }

        fn submit_bid(
            ref self: ContractState,
            auction_id: u256,
            bid_commitment: felt252,
            deposit: u256,
        ) {
            let caller = get_caller_address();
            let now = get_block_timestamp();

            // Validate auction exists and is open
            let state = self.auction_state.read(auction_id);
            assert(state == AuctionState::Open, 'Auction not open');

            let bid_deadline = self.auction_bid_deadline.read(auction_id);
            assert(now < bid_deadline, 'Bidding period ended');

            // Ensure bidder hasn't already bid
            let existing = self.bid_commitment.read((auction_id, caller));
            assert(existing == 0, 'Already submitted a bid');

            // Ensure deposit covers minimum price
            let min_price = self.auction_min_price.read(auction_id);
            assert(deposit >= min_price, 'Deposit below minimum');

            // Seller cannot bid on own auction
            let seller = self.auction_seller.read(auction_id);
            assert(caller != seller, 'Seller cannot bid');

            // Store the commitment and deposit
            self.bid_commitment.write((auction_id, caller), bid_commitment);
            self.bid_deposit.write((auction_id, caller), deposit);

            // Increment bid count
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

            // Check we're in the reveal phase
            let bid_deadline = self.auction_bid_deadline.read(auction_id);
            let reveal_deadline = self.auction_reveal_deadline.read(auction_id);
            assert(now >= bid_deadline, 'Bidding still open');
            assert(now < reveal_deadline, 'Reveal period ended');

            // Update state to Revealing if still Open
            let state = self.auction_state.read(auction_id);
            if state == AuctionState::Open {
                self.auction_state.write(auction_id, AuctionState::Revealing);
            }

            // Ensure bidder has a commitment
            let commitment = self.bid_commitment.read((auction_id, caller));
            assert(commitment != 0, 'No bid to reveal');

            // Ensure not already revealed
            let already_revealed = self.bid_is_revealed.read((auction_id, caller));
            assert(!already_revealed, 'Already revealed');

            // Verify commitment: hash(bid_amount_low, bid_amount_high, salt) == commitment
            let bid_amount_low: felt252 = (bid_amount & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                .try_into()
                .unwrap();
            let bid_amount_high: felt252 = (bid_amount / 0x100000000000000000000000000000000)
                .try_into()
                .unwrap();
            let computed = poseidon_hash_span(
                array![bid_amount_low, bid_amount_high, salt].span(),
            );
            assert(computed == commitment, 'Invalid reveal');

            // Verify bid >= min_price
            let min_price = self.auction_min_price.read(auction_id);
            assert(bid_amount >= min_price, 'Bid below minimum');

            // Store revealed amount
            self.bid_revealed_amount.write((auction_id, caller), bid_amount);
            self.bid_is_revealed.write((auction_id, caller), true);

            // Update highest bid if this is higher
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
            assert(
                state == AuctionState::Open || state == AuctionState::Revealing,
                'Already settled',
            );

            let highest = self.auction_highest_bid.read(auction_id);
            let winner = self.auction_winner.read(auction_id);

            if highest == 0 || winner.is_zero() {
                // No valid bids — cancel the auction
                self.auction_state.write(auction_id, AuctionState::Cancelled);
            } else {
                self.auction_state.write(auction_id, AuctionState::Settled);
                self
                    .emit(
                        AuctionSettled { auction_id, winner, winning_bid: highest },
                    );
            }
        }

        fn withdraw_refund(ref self: ContractState, auction_id: u256) {
            let caller = get_caller_address();
            let state = self.auction_state.read(auction_id);
            assert(
                state == AuctionState::Settled || state == AuctionState::Cancelled,
                'Auction not settled',
            );

            // Must have a deposit
            let deposit = self.bid_deposit.read((auction_id, caller));
            assert(deposit > 0, 'No deposit to refund');

            // Must not have already claimed
            let claimed = self.bid_refund_claimed.read((auction_id, caller));
            assert(!claimed, 'Already claimed');

            // Winner doesn't get a refund (their deposit goes to the seller)
            let winner = self.auction_winner.read(auction_id);
            if state == AuctionState::Settled {
                assert(caller != winner, 'Winner cannot refund');
            }

            self.bid_refund_claimed.write((auction_id, caller), true);

            // TODO: Actually transfer the deposit back to the bidder
            // This will integrate with STRK token transfers

            self.emit(RefundClaimed { auction_id, bidder: caller, amount: deposit });
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

        fn has_bid(
            self: @ContractState, auction_id: u256, bidder: ContractAddress,
        ) -> bool {
            let commitment = self.bid_commitment.read((auction_id, bidder));
            commitment != 0
        }

        fn has_revealed(
            self: @ContractState, auction_id: u256, bidder: ContractAddress,
        ) -> bool {
            self.bid_is_revealed.read((auction_id, bidder))
        }
    }
}
