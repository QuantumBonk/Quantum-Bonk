<p align="center">
  <img src="quantumbonk.png" width="200"/>
</p>

# QUANTUM BONK

> A probabilistic system fueled by bonk. Every cycle collapses into buy distribute or burn

---

## TABLE OF CONTENTS

1. [Introduction](#introduction)
2. [Core Idea](#core-idea)
3. [System Overview](#system-overview)
4. [The Quantum Cycle](#the-quantum-cycle)
5. [Entropy Source](#entropy-source)
6. [Distribution Mechanics](#distribution-mechanics)
7. [Probability Model](#probability-model)
8. [USD1 Tension](#usd1-tension)
9. [BONK Layer](#bonk-layer)
10. [Pseudocode](#pseudocode)
11. [System Properties](#system-properties)
12. [What This Is](#what-this-is)
13. [What This Is Not](#what-this-is-not)
14. [Conclusion](#conclusion)

---

## INTRODUCTION

Markets are probabilistic. Every price, every order, every outcome is the resolution of competing forces operating under uncertainty. Most token systems pretend otherwise. They offer fixed emissions, deterministic buybacks, scheduled burns. They try to make the probabilistic look mechanical.

Quantum Bonk does the opposite.

It takes the probabilistic nature of markets and makes it explicit, structural, and verifiable. The system does not decide what will happen next. It defines a space of possible outcomes, holds them in suspension, and resolves them at the moment of execution using entropy derived from on-chain data.

The outcome does not exist until it occurs.

This is not a metaphor. Until the entropy function resolves, there is no buyback, no distribution, no burn. The system is genuinely undetermined. The moment of resolution is called wave collapse, borrowing from the formalism of quantum mechanics not because this system uses quantum hardware, but because the conceptual model maps cleanly: superposition followed by measurement-induced collapse.

This document describes the full system design, mechanics, and rationale. It is part protocol specification, part experiment log.

---

## CORE IDEA

### Superposition

In quantum mechanics, a particle in superposition holds multiple states simultaneously. The state is not hidden or unknown. The state is genuinely multiple until observation forces resolution.

Quantum Bonk applies this model to token mechanics. Before each execution cycle, the system holds three possible states:

- BUYBACK: accumulated fees are used to purchase tokens from open market
- DISTRIBUTION: accumulated fees are distributed to eligible holders
- BURN: accumulated fees are used to reduce total supply

None of these outcomes is predetermined. None is more "real" than another before the cycle executes. The system is in a genuine superposition of outcomes.

### Collapse

At the moment of execution, the system derives entropy from deterministic on-chain data. This entropy is passed through a selection function that resolves to exactly one outcome. The superposition collapses.

The selection is:
- deterministic given the entropy inputs
- unpredictable before those inputs are finalized
- publicly verifiable after execution

This is the wave collapse.

### Why This Matters

Most token systems make buybacks and burns feel like governance decisions, subject to team discretion, DAO votes, or market conditions. Quantum Bonk removes discretion entirely. The outcome space is fixed. The weights are fixed. The entropy source is fixed. No one decides what happens. The block decides.

This creates a system with a character closer to a natural process than a managed treasury. It behaves. It does not comply.

---

## SYSTEM OVERVIEW

```
                         [ FEES COLLECTED ]
                                 |
                                 v
                       [ FEE ACCUMULATION ]
                        (every transaction)
                                 |
                                 v
                    +-----------------------+
                    |                       |
                    |    SUPERPOSITION      |
                    |                       |
                    |  All outcomes exist   |
                    |  simultaneously       |
                    |                       |
                    +-----------+-----------+
                                |
                   /            |            \
                  v             v             v
           [ BUYBACK ]   [ DISTRIBUTE ]   [ BURN ]
             p=0.40         p=0.40         p=0.20
                  \             |            /
                   \            v           /
                    +-----[ COLLAPSE ]-----+
                                |
                         entropy resolved
                         from block data
                                |
                    +-----------v-----------+
                    |                       |
                    |   ONE OUTCOME         |
                    |   EXECUTED            |
                    |                       |
                    +-----------------------+
```

The system runs on a 10-minute cycle. Every cycle is independent. The outcome of cycle N has no effect on the outcome of cycle N+1. There is no memory, no momentum, no trend.

---

## THE QUANTUM CYCLE

The quantum cycle is the heartbeat of the system. It executes every 10 minutes, regardless of market conditions, holder activity, or external state. The cycle cannot be paused, accelerated, or modified by any party after deployment.

### Step 1: Fee Collection

Every transaction on the Quantum Bonk token incurs a fee. This fee is routed to the cycle accumulation pool. The pool balance at the time of cycle execution is the total resource available for that cycle's outcome.

Fees are not held by a treasury. They are not accessible to any admin key. They accumulate in the contract and are consumed entirely by each cycle.

### Step 2: Superposition Entry

At the 10-minute boundary, the cycle enters superposition. At this moment, the following is true:

- The fee pool balance is known
- The eligible wallet set is computable from current chain state
- The entropy inputs do not yet exist (they depend on the block that will mine the execution transaction)

This is the window of genuine indeterminacy. The outcome cannot be known, computed, or influenced until the executing block is finalized.

### Step 3: Entropy Resolution

When the execution transaction lands in a block, the contract reads:

- `block.hash` of the current block
- `block.timestamp` at execution
- `internalSeed` maintained by the contract (updated each cycle)

These three values are combined into a single entropy value. This value is hashed and reduced to an integer in the range [0, 10000). This integer is mapped to an outcome according to the probability weights.

### Step 4: Wave Collapse

The entropy integer falls into exactly one probability band. That band corresponds to exactly one outcome. The outcome executes immediately and atomically within the same transaction.

There is no delay between collapse and execution. The outcome does not exist, and then it does, and then it has already happened.

### Step 5: Seed Update

After execution, the internal seed is updated:

```
newSeed = hash(oldSeed, entropy, outcomeId, blockNumber)
```

This ensures that the entropy source evolves across cycles and cannot be predicted even if an attacker gains insight into future block data.

---

## ENTROPY SOURCE

### Deterministic Randomness

The entropy function is deterministic: given the same inputs, it will always produce the same output. This is essential for verifiability. Anyone can re-derive the entropy from historical block data and confirm that the outcome was correct.

The inputs are:

```
entropy = keccak256(
    block.hash,
    block.timestamp,
    contract.internalSeed
)
```

The result is a 256-bit value. The lower 14 bits are extracted to produce an integer in [0, 16383]. This is normalized to [0, 9999] using modular reduction.

### Why This Is Unpredictable

Block hash and timestamp are not known until the block is mined. While a miner has theoretical influence over these values, the attack surface is narrow:

- Timestamp can be shifted by a few seconds; this has minimal effect on a 14-bit extraction
- Block hash manipulation requires reordering or discarding blocks, which is economically costly on most chains
- The internal seed is updated each cycle and depends on prior outcomes, making long-range prediction compounding in difficulty

This design does not claim to be immune to adversarial entropy manipulation. It claims to be sufficiently resistant for the probabilistic token mechanic described here, where no single outcome provides enough economic incentive to justify the cost of a block-level attack.

### Verifiability

Every cycle execution emits an event containing:

```
event CycleExecuted(
    uint256 indexed cycleId,
    bytes32 entropyHash,
    uint16 entropyValue,
    uint8 outcomeId,
    uint256 feePool
);
```

Anyone can verify the outcome by:

1. Retrieving the block hash and timestamp from the block that executed the cycle
2. Retrieving the internal seed from the prior cycle event
3. Recomputing the entropy hash
4. Confirming the normalized value falls in the declared outcome band

The system is fully transparent and inspectable.

---

## DISTRIBUTION MECHANICS

### Eligibility

When DISTRIBUTION is selected, the system must identify 50 wallets to receive equal shares of the fee pool. Eligibility is determined at the moment of execution. There are no snapshots, no staking requirements, no registration. Eligibility is live.

A wallet is eligible if:

- It holds at least `MIN_HOLD_THRESHOLD` tokens at the block of execution
- It has executed at least one transaction in the prior `ACTIVITY_WINDOW` blocks
- It is not the zero address, the contract address, or any address on the exclusion list

The `MIN_HOLD_THRESHOLD` and `ACTIVITY_WINDOW` are set at deployment and cannot be changed.

### Selection

From the eligible set, the system selects 50 wallets using deterministic entropy. The selection process is a Fisher-Yates-style shuffle seeded with the cycle entropy:

```
function selectWallets(address[] eligibleSet, bytes32 entropy)
    returns (address[] memory winners)
{
    // Seed a local PRNG with cycle entropy
    bytes32 seed = entropy;
    uint256 n = eligibleSet.length;

    for (uint256 i = 0; i < 50 && i < n; i++) {
        seed = keccak256(seed, i);
        uint256 j = i + (uint256(seed) % (n - i));
        // swap eligibleSet[i] and eligibleSet[j]
        address temp = eligibleSet[i];
        eligibleSet[i] = eligibleSet[j];
        eligibleSet[j] = temp;
    }

    // Return first 50
    winners = eligibleSet[0:50];
}
```

Each selected wallet receives an equal share: `feePool / 50`.

### Fairness Properties

This distribution model has the following properties:

- No wallet can increase its probability of selection by holding more tokens, beyond meeting the minimum threshold
- No wallet can register or signal in advance
- The selection is determined entirely by entropy that does not exist at the time of any strategic action
- Large holders and small holders meeting the minimum threshold have equal selection probability

This is not a yield mechanism. It is a probabilistic redistribution event. Expected value over many cycles converges toward zero net gain for any individual holder, but individual cycles can produce significant local transfers.

---

## PROBABILITY MODEL

### Default Weights

The outcome probability weights are set at deployment:

| Outcome      | Weight | Probability |
|--------------|--------|-------------|
| DISTRIBUTE   | 4000   | 40.00%      |
| BUYBACK      | 4000   | 40.00%      |
| BURN         | 2000   | 20.00%      |
| **TOTAL**    | **10000** | **100.00%** |

The entropy value is normalized to [0, 9999]. Outcome mapping:

```
[0, 3999]     -> DISTRIBUTE
[4000, 7999]  -> BUYBACK
[8000, 9999]  -> BURN
```

### Weight Rationale

DISTRIBUTE and BUYBACK are weighted equally at 40% each. This creates symmetric pressure on price: distribution events push capital to holders without affecting supply, buyback events apply direct buy pressure on open market. Neither effect dominates in expectation.

BURN is weighted lower at 20%. Burns are deflationary but irreversible. Aggressive burn schedules in other tokens have historically contributed to price manipulation narratives. A lower burn probability keeps the supply reduction meaningful but not dominant.

### BONK Weight Modifier

If the BONK layer is enabled, wallet-level BONK holdings can shift the effective probability weights. See BONK Layer section.

### Long-Run Behavior

Over a sufficiently large number of cycles, the system will approximate:

- 40% of fee volume applied as buy pressure
- 40% of fee volume redistributed to holders
- 20% of fee volume permanently removed from circulation

In practice, cycle-to-cycle variance is high. Runs of consecutive BURN outcomes are possible. Runs of consecutive DISTRIBUTE outcomes are possible. The system does not smooth variance. It expresses it.

---

## USD1 TENSION

### The Anchor Premise

Quantum Bonk is nominally denominated with reference to a $1 value. Buybacks are sized against a $1 target. Distribution amounts are calculated relative to a $1 peg. The system contains implicit price-stabilizing mechanics.

This is the USD1 narrative: the system tries to behave like a dollar-anchored instrument.

### Why It Cannot Hold

The probabilistic cycle structure makes true stability impossible. A genuine stable token requires:

- Predictable redemption
- Deterministic collateral management
- Removal of supply-side variance

Quantum Bonk has none of these. The buyback mechanic applies buy pressure, but only when the entropy resolves to BUYBACK. In cycles that resolve to BURN, capital is destroyed. In cycles that resolve to DISTRIBUTE, capital is redistributed but does not create price support.

The stabilizing mechanics are real. They operate. They simply do not operate consistently. Whether a given 10-minute window sees a buyback or a burn or a distribution depends on entropy, not on price deviation from the target.

### The Productive Tension

This tension is a feature, not a failure. A system that truly stabilized would be uninteresting. The USD1 target creates an attractor, a gravitational reference point around which the price orbits. But the orbit is not circular. It is chaotic, within bounds, pulled by the attractor but perturbed constantly by probabilistic cycle outcomes.

The attractor is real. The stability is not.

This is an honest representation of what algorithmic stabilization actually is: a tendency, not a guarantee.

---

## BONK LAYER

### Why BONK

BONK is an existing token with established distribution and market liquidity. Integrating BONK creates a secondary entropy axis: instead of purely block-derived randomness, the system incorporates an external economic signal.

A percentage of the fee pool in each cycle is converted to BONK before the cycle executes. This BONK is held in the entropy reserve. It does not directly affect outcomes. It affects the probability weights used to evaluate outcomes.

### Entropy Fuel

BONK functions as entropy fuel. The amount of BONK in the entropy reserve at the time of cycle execution modifies the probability weight vector. The modification is bounded:

```
bonkModifier = min(reserveBONK / BONK_SCALE_FACTOR, MAX_MODIFIER)

effectiveDistributeWeight = BASE_DISTRIBUTE_WEIGHT + bonkModifier
effectiveBuybackWeight    = BASE_BUYBACK_WEIGHT - bonkModifier / 2
effectiveBurnWeight       = BASE_BURN_WEIGHT - bonkModifier / 2
```

When the BONK reserve is high, DISTRIBUTE probability increases. When the BONK reserve is low or depleted, weights revert to their base values.

This creates a secondary dynamic: the BONK price and reserve level become economic inputs to the distribution probability. Holders who also hold BONK observe that high BONK accumulation periods increase the likelihood of distribution cycles.

### Optional Holder Weight

There is an optional configuration in which individual holders holding above a BONK threshold receive elevated selection probability during DISTRIBUTE cycles. This is disabled by default.

When enabled, eligible wallets are bucketed:

```
standardEligible: holds MIN_HOLD_THRESHOLD tokens, does not hold BONK_MIN
elevatedEligible: holds MIN_HOLD_THRESHOLD tokens, also holds BONK_MIN BONK
```

Elevated wallets occupy two slots in the selection pool. Standard wallets occupy one. The effect is a doubling of selection probability for holders who maintain both positions.

This is disclosed transparently. It is not hidden weighting.

### Noise Introduction

The BONK layer introduces deliberate noise into the system. The BONK price is external, volatile, and influenced by factors entirely unrelated to Quantum Bonk. This means the effective probability weights fluctuate based on market conditions in a separate ecosystem.

This is intentional. A system sensitive to external entropy is harder to game than a system with fixed, known weights. The BONK integration exposes the probability model to real-world noise, making it more robust against manipulation by any single actor.

---

## PSEUDOCODE

### Core Cycle Function

```javascript
function quantumCycle() {
    require(block.timestamp >= lastCycleTime + CYCLE_INTERVAL);

    // Step 1: Read fee pool
    uint256 feePool = accumulatedFees;
    accumulatedFees = 0;

    // Step 2: Derive entropy
    bytes32 entropy = keccak256(
        block.hash,
        block.timestamp,
        internalSeed
    );

    // Step 3: Normalize entropy to [0, 9999]
    uint16 entropyValue = uint16(uint256(entropy) % 10000);

    // Step 4: Select outcome
    Outcome outcome = selectOutcome(entropyValue);

    // Step 5: Execute outcome
    if (outcome == Outcome.BUYBACK) {
        executeBuyback(feePool);
    }

    if (outcome == Outcome.DISTRIBUTE) {
        address[] memory eligible = getEligibleWallets();
        address[] memory winners = selectWallets(eligible, entropy);
        distribute(winners, feePool);
    }

    if (outcome == Outcome.BURN) {
        burnTokens(feePool);
    }

    // Step 6: Update seed and emit event
    internalSeed = keccak256(internalSeed, entropy, uint8(outcome), block.number);
    lastCycleTime = block.timestamp;

    emit CycleExecuted(cycleId++, entropy, entropyValue, uint8(outcome), feePool);
}
```

### Outcome Selection

```javascript
function selectOutcome(uint16 entropyValue) returns (Outcome) {
    uint16 cursor = 0;

    for (uint256 i = 0; i < outcomeWeights.length; i++) {
        cursor += outcomeWeights[i];
        if (entropyValue < cursor) {
            return Outcome(i);
        }
    }

    revert("OUTCOME_SELECTION_FAILED");
}
```

### Wallet Selection

```javascript
function selectWallets(
    address[] memory eligibleSet,
    bytes32 entropy
) returns (address[] memory winners) {
    uint256 n = eligibleSet.length;
    require(n >= 50, "INSUFFICIENT_ELIGIBLE_WALLETS");

    bytes32 seed = entropy;

    for (uint256 i = 0; i < 50; i++) {
        seed = keccak256(seed, bytes32(i));
        uint256 j = i + (uint256(seed) % (n - i));

        address temp = eligibleSet[i];
        eligibleSet[i] = eligibleSet[j];
        eligibleSet[j] = temp;
    }

    winners = new address[](50);
    for (uint256 i = 0; i < 50; i++) {
        winners[i] = eligibleSet[i];
    }
}
```

### Buyback Execution

```javascript
function executeBuyback(uint256 feePool) internal {
    // Convert fee pool to purchase
    // Route through DEX
    uint256 tokensBought = swapFeesForTokens(feePool);

    // Tokens are retained by contract or redistributed
    // based on configuration
    totalBoughtBack += tokensBought;

    emit BuybackExecuted(feePool, tokensBought);
}
```

### Burn Execution

```javascript
function burnTokens(uint256 feePool) internal {
    // Convert fee pool and burn equivalent token value
    uint256 burnAmount = computeBurnAmount(feePool);

    _burn(address(this), burnAmount);
    totalBurned += burnAmount;

    emit BurnExecuted(feePool, burnAmount);
}
```

### Cycle Simulation (JavaScript)

```javascript
// cycleSimulation.js
// Simulates N quantum cycles with given weights

const crypto = require('crypto');

const WEIGHTS = {
    DISTRIBUTE: 4000,
    BUYBACK: 4000,
    BURN: 2000,
};

function deriveEntropy(blockHash, timestamp, seed) {
    const input = blockHash + timestamp.toString() + seed;
    const hash = crypto.createHash('sha256').update(input).digest('hex');
    return parseInt(hash.slice(0, 4), 16) % 10000;
}

function selectOutcome(entropyValue) {
    let cursor = 0;
    for (const [outcome, weight] of Object.entries(WEIGHTS)) {
        cursor += weight;
        if (entropyValue < cursor) return outcome;
    }
    throw new Error('Selection failed');
}

function simulateCycles(n, initialSeed) {
    let seed = initialSeed;
    const results = { DISTRIBUTE: 0, BUYBACK: 0, BURN: 0 };

    for (let i = 0; i < n; i++) {
        // Simulate block data
        const blockHash = crypto.randomBytes(32).toString('hex');
        const timestamp = Date.now() + i * 600000;

        const entropyValue = deriveEntropy(blockHash, timestamp, seed);
        const outcome = selectOutcome(entropyValue);
        results[outcome]++;

        // Update seed
        seed = crypto.createHash('sha256')
            .update(seed + entropyValue.toString() + outcome)
            .digest('hex');
    }

    return results;
}

const N = 10000;
const results = simulateCycles(N, 'genesis_seed_0x01');

console.log(`Simulation: ${N} cycles`);
console.log(`DISTRIBUTE: ${results.DISTRIBUTE} (${(results.DISTRIBUTE/N*100).toFixed(2)}%)`);
console.log(`BUYBACK:    ${results.BUYBACK} (${(results.BUYBACK/N*100).toFixed(2)}%)`);
console.log(`BURN:       ${results.BURN} (${(results.BURN/N*100).toFixed(2)}%)`);
```

---

## SYSTEM PROPERTIES

### Deterministic Given Inputs

Every outcome is fully determined by the entropy inputs. No computation inside the system is probabilistic in the classical sense. The randomness is sourced externally (from block data) and processed deterministically. Two identical entropy inputs will always produce identical outputs.

### Inspectable

The full state of the system is on-chain and readable. The current internal seed, accumulated fees, last cycle time, weight configuration, and full cycle history are accessible without permission. There is no privileged view.

### No Hidden Logic

The contract contains no admin functions that affect outcome selection, weight modification, or wallet eligibility after deployment. The owner can update the exclusion list (to block zero addresses or known contract addresses) but cannot modify probability weights, cycle interval, or fee routing.

### No Admin Control Over Outcomes

There is no function in the contract that allows any party to force a specific outcome. The cycle can be triggered by any caller once the interval has elapsed, but the caller cannot influence what outcome results from the trigger.

### Immutable After Deployment

The core cycle parameters are set at deployment:

- `CYCLE_INTERVAL`: 600 seconds
- `MIN_HOLD_THRESHOLD`: set at deploy
- `ACTIVITY_WINDOW`: set at deploy
- `outcomeWeights`: [4000, 4000, 2000]
- `BONK_SCALE_FACTOR`: set at deploy

These cannot be changed.

### Composable Event Stream

Every cycle emits a fully structured event. The event stream can be consumed by external contracts, indexers, dashboards, or analytics systems. The system makes no assumptions about downstream consumers.

---

## WHAT THIS IS

Quantum Bonk is an experiment in probabilistic market design. It exists to answer a specific question: what happens when you make the stochastic nature of market mechanics explicit, immutable, and structural?

Most token economics are designed to appear stable and predictable. Emission schedules, vesting cliffs, governance-controlled buybacks. These designs impose a fictional determinism on fundamentally uncertain systems.

This experiment does the opposite. It acknowledges uncertainty as the primary property of the system and builds mechanics that operate transparently within that uncertainty.

The USD1 tension, the BONK entropy layer, the live eligibility model, the wave collapse mechanic: these are not features added to make the token interesting. They are the direct result of taking the probabilistic premise seriously and designing consistently from it.

Whether this produces a viable token economy is an open question. The system will run, and the data will be available, and anyone can evaluate it.

---

## WHAT THIS IS NOT

### Not Quantum Computing

This system does not use quantum hardware, quantum gates, quantum circuits, or any computation that requires quantum mechanical properties to execute. The use of "quantum" in the name refers to the conceptual model of superposition and collapse, not to the computational substrate.

### Not AI Trading

There is no machine learning, neural network, or AI agent involved in outcome selection. The selection function is a deterministic mapping from an integer to an enum. It has no memory, no adaptation, and no learning.

### Not Guaranteed Profit

Distribution events are probabilistic. Holding tokens does not guarantee receipt of distributions. Over many cycles, the expected value of distributions for any individual wallet depends on how often that wallet is eligible and selected, which in turn depends on entropy that cannot be predicted.

There is no investment return implied, promised, or suggested by the system design.

### Not a Stable Coin

The USD1 tension is described in full. The system contains mechanics that push toward a $1 reference price, but those mechanics are probabilistic and inconsistent. The token is not collateralized. It is not redeemable. It does not maintain a peg.

### Not Audited

This repository represents a design specification and prototype implementation. The contracts have not been professionally audited. Do not deploy with real assets without a thorough security review.

---

## CONCLUSION

Quantum Bonk is a narrow experiment with a clear premise. Markets are probabilistic. Most token systems pretend they are not. This one does not pretend.

The cycle runs. The entropy resolves. The outcome executes. No one decides.

The system will produce data: outcome frequencies, distribution patterns, price behavior relative to the USD1 attractor, BONK reserve dynamics. That data will be informative regardless of whether the token itself succeeds or fails by conventional metrics.

The repository is open. The contract logic is public. The cycle simulation can be run locally. The event stream is permissionlessly readable.

That is what this is. It is what it says it is.

---

## REPOSITORY STRUCTURE

```
/quantum-bonk
  README.md
  /contracts
    QuantumBonk.sol
    interfaces/
      IQuantumBonk.sol
      IEntropyProvider.sol
  /docs
    architecture.md
    entropy.md
    distribution.md
  /scripts
    cycleSimulation.js
    verifyOutcome.js
    eligibilityChecker.js
  /test
    QuantumBonk.test.js
```

---

## LICENSE

MIT. Use freely. No warranty expressed or implied.

---

*Version 0.1.0 | Initial specification*
