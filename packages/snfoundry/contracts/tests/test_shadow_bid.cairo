#[starknet::interface]
trait IShadowBid<TContractState> {
    fn create_auction(
        ref self: TContractState,
        item_hash: felt252,
        min_price: u256,
        bid_duration: u64,
        reveal_duration: u64,
    ) -> u256;
    fn submit_bid(
        ref self: TContractState,
        auction_id: u256,
        bid_commitment: felt252,
        deposit: u256,
        proof: Span<felt252>,
    );
    fn reveal_bid(
        ref self: TContractState,
        auction_id: u256,
        bid_amount: u256,
        salt: felt252,
    );
    fn settle_auction(ref self: TContractState, auction_id: u256);
    fn withdraw_refund(ref self: TContractState, auction_id: u256);
    fn claim_seller_payment(ref self: TContractState, auction_id: u256);
    fn get_auction(self: @TContractState, auction_id: u256) -> AuctionInfo;
}

#[derive(Drop, Copy, Serde, PartialEq)]
struct AuctionInfo {
    seller: starknet::ContractAddress,
    item_hash: felt252,
    min_price: u256,
    bid_deadline: u64,
    reveal_deadline: u64,
    state: AuctionState,
    bid_count: u32,
    highest_bid: u256,
    winner: starknet::ContractAddress,
}

#[derive(Drop, Copy, Serde, PartialEq)]
enum AuctionState {
    Open,
    Revealing,
    Settled,
    Cancelled,
}

// -----------------------------------------------------------------------------
// Mocks
// -----------------------------------------------------------------------------

#[starknet::interface]
trait IUltraKeccakZKHonkVerifier<TContractState> {
    fn verify_ultra_keccak_zk_honk_proof(
        self: @TContractState, full_proof_with_hints: Span<felt252>,
    ) -> Result<Span<u256>, felt252>;
}

#[starknet::contract]
mod MockVerifier {
    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl VerifierImpl of super::IUltraKeccakZKHonkVerifier<ContractState> {
        fn verify_ultra_keccak_zk_honk_proof(
            self: @ContractState, full_proof_with_hints: Span<felt252>,
        ) -> Result<Span<u256>, felt252> {
            // Mock logic: return success if proof is not empty, else fail
            // Return dummy public inputs: [min_price, max_price, commitment]
            // We'll hardcode values matching the test case expectation
            // Or better: decode them from the "proof" which we treat as data container in tests
            
            if full_proof_with_hints.len() == 0 {
                return Result::Err('Mock verification failed');
            }

            // Expect proof to contain: [min_price_low, min_price_high, max_price_low, max_price_high, comm_low, comm_high]
            // Actually, verify returns Span<u256>.
            // Let's just return what we put in the proof for flexibility.
            // Format: [min_price, max_price, commitment] (3x u256 = 6x felt? No, result is Span<u256>)
            
            // Simpler mock: Just return fixed valid outputs for our test case
            // Let's say we always return: [100, u64::MAX, commitment_from_proof[0]]
            // Use the first element of proof as the 'commitment' to allow varying it.
            
            let min_price = 100_u256;
            let max_price = 18446744073709551615_u256; // u64::MAX
            // We need the commitment to match what the contract expects.
            // The contract passes `proof` to the verifier.
            // We can encode the expected commitment in the first felt of the proof.
            let comm_felt = *full_proof_with_hints.at(0);
            let commitment: u256 = comm_felt.into(); // Simple cast for mock

            let mut output = ArrayTrait::new();
            output.append(min_price);
            output.append(max_price);
            output.append(commitment);
            
            Result::Ok(output.span())
        }
    }
}

#[starknet::contract]
mod MockToken {
    use openzeppelin_token::erc20::ERC20Component;
    use starknet::ContractAddress;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    impl ERC20HooksImpl of ERC20Component::ERC20HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC20Component::ComponentState<ContractState>,
            from: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {}
        fn after_update(
            ref self: ERC20Component::ComponentState<ContractState>,
            from: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {}
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        let name = "MockToken";
        let symbol = "MTK";
        self.erc20.initializer(name, symbol);
    }
    
    #[external(v0)]
    fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
        self.erc20.mint(recipient, amount);
    }
    
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use contracts::shadow_bid::{
        IShadowBidDispatcher, IShadowBidDispatcherTrait, AuctionState,
    };

    use starknet::{ContractAddress, contract_address_const};
    use snforge_std::{
        declare, ContractClassTrait, start_cheat_caller_address, stop_cheat_caller_address,
        DeclareResultTrait
    };

    use core::hash::HashStateTrait;
    use core::pedersen::PedersenTrait;

    #[starknet::interface]
    trait IMockToken<TContractState> {
        fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
        fn approve(ref self: TContractState, spender: ContractAddress, amount: u256);
    }

    fn deploy_setup() -> (IShadowBidDispatcher, IMockTokenDispatcher, ContractAddress, ContractAddress) {
        // 1. Deploy Mock Verifier
        let verifier_class = declare("MockVerifier").unwrap().contract_class();
        let (verifier_addr, _) = verifier_class.deploy(@array![]).unwrap();

        // 2. Deploy Mock Token
        let token_class = declare("MockToken").unwrap().contract_class();
        let (token_addr, _) = token_class.deploy(@array![]).unwrap();
        let token = IMockTokenDispatcher { contract_address: token_addr };

        // 3. Deploy ShadowBid
        let contract_class = declare("ShadowBid").unwrap().contract_class();
        let mut calldata = ArrayTrait::new();
        calldata.append(verifier_addr.into());
        calldata.append(token_addr.into());
        
        // Note: ShadowBid constructor expects arguments.
        // It takes (verifier_addr, payment_token).
        
        let (contract_addr, _) = contract_class.deploy(@calldata).unwrap();
        let dispatcher = IShadowBidDispatcher { contract_address: contract_addr };

        (dispatcher, token, contract_addr, token_addr)
    }

    #[test]
    fn test_create_auction() {
        let (shadow_bid, _, _, _) = deploy_setup();
        
        let item_hash = 0x12345;
        let min_price = 100_u256;
        let bid_duration = 100;
        let reveal_duration = 50;

        let auction_id = shadow_bid.create_auction(
            item_hash, min_price, bid_duration, reveal_duration
        );

        assert(auction_id == 1, 'Auction ID should be 1');
        
        let info = shadow_bid.get_auction(auction_id);
        assert(info.min_price == min_price, 'Min price mismatch');
        assert(info.state == AuctionState::Open, 'State should be Open');
    }

    #[test]
    fn test_submit_bid() {
        let (shadow_bid, token, shadow_bid_addr, _) = deploy_setup();
        let bidder = contract_address_const::<0x456>();
        
        // Mint tokens to bidder
        let deposit = 200_u256;
        token.mint(bidder, 1000_u256);
        
        start_cheat_caller_address(token.contract_address, bidder);
        token.approve(shadow_bid_addr, deposit);
        stop_cheat_caller_address(token.contract_address);

        // Create Auction
        let owner = contract_address_const::<0x123>();
        start_cheat_caller_address(shadow_bid.contract_address, owner);
        let auction_id = shadow_bid.create_auction(0x12345, 100, 100, 50);
        stop_cheat_caller_address(shadow_bid.contract_address);

        // Prepare Bid
        let bid_amount = 150;
        let salt = 999;
        let bid_felt: felt252 = bid_amount.try_into().unwrap();
        
        // Calculate expected commitment (Pedersen)
        let commitment = PedersenTrait::new(0).update(bid_felt).update(salt).finalize();
        
        // Prepare Mock Proof (first element = commitment)
        let mut proof_arr = ArrayTrait::new();
        proof_arr.append(commitment); 
        let proof = proof_arr.span();

        // Submit Bid
        start_cheat_caller_address(shadow_bid.contract_address, bidder);
        shadow_bid.submit_bid(auction_id, commitment, deposit, proof);
        stop_cheat_caller_address(shadow_bid.contract_address);

        let info = shadow_bid.get_auction(auction_id);
        assert(info.bid_count == 1, 'Bid count should be 1');
    }
}
