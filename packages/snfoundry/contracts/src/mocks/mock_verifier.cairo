#[starknet::interface]
trait IUltraKeccakZKHonkVerifier<TContractState> {
    fn verify_ultra_keccak_zk_honk_proof(
        ref self: TContractState, full_proof_with_hints: Span<felt252>,
    ) -> Result<Span<u256>, felt252>;
}

#[starknet::contract]
mod MockVerifier {
    use super::IUltraKeccakZKHonkVerifier;
    
    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl MockVerifierImpl of IUltraKeccakZKHonkVerifier<ContractState> {
        fn verify_ultra_keccak_zk_honk_proof(
            ref self: ContractState, full_proof_with_hints: Span<felt252>
        ) -> Result<Span<u256>, felt252> {
            // Always return success for mock
            Result::Ok(array![].span())
        }
    }
}
