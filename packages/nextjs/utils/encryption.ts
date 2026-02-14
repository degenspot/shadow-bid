// Stub for encryption utility
// Currently not using ElGamal for the MVP flow (commit-reveal only)

export const encryptBid = (
    amount: bigint,
    publicKey: string,
    randomness: bigint
): { c1: string; c2: string } => {
    return { c1: "0x0", c2: "0x0" };
};
