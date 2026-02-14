import { hash } from "starknet";

// Commits to a value using a salt
// C = Poseidon(value, salt)
export const calculateCommitment = (value: bigint, salt: bigint): string => {
    // poseidonHashMany takes array of BigNumberish
    // Returns hex string
    return hash.computePoseidonHashOnElements([value, salt]);
};
