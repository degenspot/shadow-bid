# ShadowBid ZK Circuits

Noir circuits for zero-knowledge bid range proofs used by the ShadowBid protocol.

## Circuit: Bid Range Proof

Proves that:
- `bid_amount >= min_price` (bid meets minimum)
- `commitment == hash(bid_amount, salt)` (commitment is valid)

Without revealing the actual `bid_amount`.

## Setup

```bash
# Install Noir
make install-noir

# Install Barretenberg (prover backend)
make install-barretenberg

# Build circuit
nargo compile

# Run tests
nargo test

# Generate witness
nargo execute

# Generate verification key
bb write_vk
```
