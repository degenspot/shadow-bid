# 🛡️ ShadowBid — Private Sealed-Bid Auction Platform

> A privacy-preserving sealed-bid auction platform built on [Starknet](https://starknet.io), powered by zero-knowledge proofs.

Built for the **[Re{define} Hackathon](https://hackathon.starknet.org/)** — Privacy Track.

---

## Overview

ShadowBid enables truly private auctions on-chain. Bids are committed as cryptographic hashes during the bidding phase and only revealed after the deadline. Zero-knowledge proofs ensure bid validity without exposing amounts.

### How It Works

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  CREATE   │───▶│   BID     │───▶│  REVEAL  │───▶│  SETTLE  │
│  AUCTION  │    │ (sealed)  │    │ (verify) │    │ (winner) │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
     Seller         Bidders        Bidders        Anyone
  sets params    submit hash    reveal amount    settle & claim
```

1. **Create** — Seller creates an auction with item details, minimum price, and deadline
2. **Bid** — Bidders submit Poseidon hash commitments of their bids (amount stays hidden)
3. **Reveal** — After bidding closes, bidders reveal their bids; contract verifies against commitments
4. **Settle** — Highest valid bid wins; losers can claim refunds

### Key Privacy Features

- **🔒 Sealed bids** — Amounts hidden via Poseidon hash commitments
- **📜 ZK range proofs** — Noir circuits prove `bid ≥ min_price` without revealing the amount
- **🛡️ Front-running protection** — Nobody can see bids during the bidding phase
- **⚡ STARK verification** — Garaga verifies Noir proofs on-chain

---

## Tech Stack

| Layer | Technology | Purpose |
|---|---|---|
| Smart Contracts | **Cairo** (Starknet) | Auction logic, bid storage, state machine |
| ZK Proofs | **Noir** + **Garaga** | Prove bid validity without revealing amounts |
| Frontend | **Next.js** + **Starknet.js** | User-facing auction interface |
| Wallet | **StarknetKit** | Wallet connection (Argent, Braavos) |
| Scaffold | **Scaffold-Stark 2** | Development framework |

---

## Project Structure

```
shadow-bid/
├── packages/
│   ├── snfoundry/          # Cairo smart contracts
│   │   ├── contracts/
│   │   │   └── src/
│   │   │       ├── lib.cairo
│   │   │       └── shadow_bid.cairo    # Main auction contract
│   │   └── scripts-ts/
│   │       └── deploy.ts               # Deployment script
│   ├── circuits/            # Noir ZK circuits
│   │   ├── Nargo.toml
│   │   └── src/
│   │       └── main.nr                 # Bid range proof circuit
│   └── nextjs/              # Frontend application
│       ├── app/
│       └── components/
├── package.json
└── README.md
```

---

## Getting Started

### Prerequisites

- [Node.js](https://nodejs.org/) (>= v22)
- [Yarn](https://yarnpkg.com/)
- [Scarb](https://docs.swmansion.com/scarb/) (Cairo package manager)
- [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/)

### Installation

```bash
# Clone the repository
git clone https://github.com/degenspot/shadow-bid.git
cd shadow-bid

# Install dependencies
yarn install
```

### Development

```bash
# Terminal 1: Start local Starknet devnet
yarn chain

# Terminal 2: Deploy contracts
yarn deploy

# Terminal 3: Start the frontend
yarn start
```

Visit `http://localhost:3000` to interact with the app.

### Cairo Contract Development

```bash
# Compile contracts
yarn compile

# Run tests
yarn test
```

---

## Hackathon Context

| Detail | Value |
|---|---|
| **Hackathon** | [Re{define}](https://hackathon.starknet.org/) by Starknet Foundation |
| **Track** | Privacy ($9,675 STRK) |
| **Timeline** | Feb 1 – Feb 28, 2026 |
| **Submission** | [DoraHacks](https://dorahacks.io/hackathon/redefine/detail) |

---

## Key Resources

- [Starknet Docs](https://docs.starknet.io)
- [Cairo Book](https://book.cairo-lang.org/)
- [Garaga Documentation](https://garaga.gitbook.io/garaga)
- [Tongo SDK](https://docs.tongo.cash/sdk/quick-start.html)
- [Scaffold-Stark 2](https://scaffoldstark.com/docs)

---

## Team

Built with ❤️ for the Starknet Re{define} Hackathon.

## License

MIT
