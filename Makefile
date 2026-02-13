# ============================================================
# ShadowBid — Build & Deploy Makefile
# ============================================================
# Pinned versions (tested compatible combination from scaffold-garaga)
NOIR_VERSION    := 1.0.0-beta.16
BB_VERSION      := 3.0.0-nightly.20251104
GARAGA_VERSION  := 1.0.1
DEVNET_VERSION  := 0.6.1

CIRCUIT_DIR     := packages/circuits
CONTRACT_DIR    := packages/snfoundry/contracts
VERIFIER_DIR    := $(CONTRACT_DIR)/src/verifier

# ============================================================
#                     INSTALL TOOLS
# ============================================================

.PHONY: install-noir install-bb install-garaga install-all check-versions

install-noir:
	@echo "📦 Installing Noir $(NOIR_VERSION)..."
	curl -L https://raw.githubusercontent.com/noir-lang/noirup/refs/heads/main/install | bash
	noirup --version $(NOIR_VERSION)
	@echo "✅ Noir installed: $$(nargo --version)"

install-bb:
	@echo "📦 Installing Barretenberg $(BB_VERSION)..."
	curl -L https://raw.githubusercontent.com/AztecProtocol/aztec-packages/refs/heads/master/barretenberg/bbup/install | bash
	bbup --version $(BB_VERSION)
	@echo "✅ Barretenberg installed: $$(bb --version)"

install-garaga:
	@echo "📦 Installing Garaga $(GARAGA_VERSION)..."
	conda run -n garaga-env pip install garaga==$(GARAGA_VERSION)
	@echo "✅ Garaga installed: $$(conda run -n garaga-env garaga --version)"

install-all: install-noir install-bb install-garaga
	@echo "🎉 All tools installed!"

check-versions:
	@echo "🔍 Checking tool versions..."
	@echo "Noir:          $$(nargo --version 2>/dev/null || echo 'NOT INSTALLED')"
	@echo "Barretenberg:  $$(bb --version 2>/dev/null || echo 'NOT INSTALLED')"
	@echo "Garaga:        $$(garaga --version 2>/dev/null || echo 'NOT INSTALLED')"
	@echo "Scarb:         $$(scarb --version 2>/dev/null || echo 'NOT INSTALLED')"
	@echo "snforge:       $$(snforge --version 2>/dev/null || echo 'NOT INSTALLED')"

# ============================================================
#                   CIRCUIT (Noir)
# ============================================================

.PHONY: build-circuit exec-circuit prove-circuit gen-vk

build-circuit:
	@echo "🔨 Building Noir circuit..."
	cd $(CIRCUIT_DIR) && nargo build
	@echo "✅ Circuit compiled"

test-circuit:
	@echo "🧪 Testing Noir circuit..."
	cd $(CIRCUIT_DIR) && nargo test
	@echo "✅ Circuit tests passed"

exec-circuit:
	@echo "▶️  Executing Noir circuit..."
	cd $(CIRCUIT_DIR) && nargo execute witness

gen-vk:
	@echo "🔑 Generating verification key..."
	bb write_vk --scheme ultra_honk \
		--oracle_hash keccak \
		-b ./$(CIRCUIT_DIR)/target/shadow_bid_circuits.json \
		-o ./$(CIRCUIT_DIR)/target
	@echo "✅ Verification key generated"

prove-circuit:
	@echo "🔐 Generating proof..."
	bb prove --scheme ultra_honk \
		--oracle_hash keccak \
		-b ./$(CIRCUIT_DIR)/target/shadow_bid_circuits.json \
		-w ./$(CIRCUIT_DIR)/target/witness.gz \
		-k ./$(CIRCUIT_DIR)/target/vk \
		-o ./$(CIRCUIT_DIR)/target
	@echo "✅ Proof generated"

# ============================================================
#                 VERIFIER (Garaga)
# ============================================================

.PHONY: gen-verifier build-verifier

gen-verifier:
	@echo "⚙️  Generating Cairo verifier from Noir circuit..."
	cd $(CONTRACT_DIR) && source ~/.zshrc && conda activate garaga-env && \
		PATH="$(HOME)/.asdf/installs/scarb/2.15.1/bin:$$PATH" garaga gen \
		--system ultra_keccak_zk_honk \
		--vk $(CURDIR)/$(CIRCUIT_DIR)/target/vk \
		--project-name verifier
	@echo "✅ Cairo verifier generated at $(VERIFIER_DIR)"

build-verifier:
	@echo "🔨 Building verifier contract..."
	cd $(VERIFIER_DIR) && scarb build
	@echo "✅ Verifier contract compiled"

# ============================================================
#                 CONTRACTS (Cairo)
# ============================================================

.PHONY: build-contracts test-contracts

build-contracts:
	@echo "🔨 Building ShadowBid contracts..."
	cd $(CONTRACT_DIR) && scarb build
	@echo "✅ Contracts compiled"

test-contracts:
	@echo "🧪 Running contract tests..."
	cd packages/snfoundry && snforge test
	@echo "✅ Contract tests passed"

# ============================================================
#                    DEVNET
# ============================================================

.PHONY: devnet deploy

devnet:
	@echo "🌐 Starting Starknet devnet..."
	starknet-devnet --accounts=2 --seed=0 --initial-balance=100000000000000000000000

deploy:
	@echo "🚀 Deploying contracts to devnet..."
	cd packages/snfoundry && yarn deploy
	@echo "✅ Contracts deployed"

# ============================================================
#                   FRONTEND
# ============================================================

.PHONY: dev

dev:
	@echo "🖥️  Starting frontend..."
	cd packages/nextjs && yarn dev

# ============================================================
#              FULL PIPELINE
# ============================================================

.PHONY: pipeline

pipeline: build-circuit gen-vk gen-verifier build-contracts test-contracts
	@echo "🎉 Full pipeline complete!"
