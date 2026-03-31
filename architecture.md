# QUANTUM BONK: SYSTEM ARCHITECTURE

---

## OVERVIEW

Quantum Bonk is a single-contract token system augmented by an off-chain eligibility
oracle and an optional BONK entropy layer. The architecture is intentionally minimal.
No multisig. No governance. No upgradeability.

The contract is the system.

---

## COMPONENT MAP

```
+------------------------------------------------------------------+
|                        BLOCKCHAIN                                |
|                                                                  |
|   +----------------------+      +---------------------------+   |
|   |   QuantumBonk.sol    |      |      BONK Token           |   |
|   |                      |<---->|   (external contract)     |   |
|   |  - ERC20 base        |      +---------------------------+   |
|   |  - Fee collection    |                                      |
|   |  - Cycle execution   |      +---------------------------+   |
|   |  - Entropy derivation|      |      DEX Router           |   |
|   |  - Outcome dispatch  |<---->|   (Uniswap / PancakeSwap) |   |
|   |  - Burn logic        |      +---------------------------+   |
|   |  - Distribution send |                                      |
|   +----------+-----------+                                      |
|              |                                                   |
|              | emits events                                      |
|              v                                                   |
|   +----------+-----------+                                      |
|   |    Event Stream       |                                      |
|   |  CycleExecuted        |                                      |
|   |  BuybackExecuted      |                                      |
|   |  BurnExecuted         |                                      |
|   |  DistributionExecuted |                                      |
|   +----------------------+                                       |
+------------------------------------------------------------------+
                              |
                              | indexed by
                              v
+------------------------------------------------------------------+
|                     OFF-CHAIN LAYER                              |
|                                                                  |
|   +----------------------+      +---------------------------+   |
|   |  Eligibility Oracle   |      |   Cycle Trigger Bot       |   |
|   |                      |      |                           |   |
|   |  - Indexes transfers  |      |  - Watches lastCycleTime  |   |
|   |  - Tracks balances    |      |  - Calls quantumCycle()   |   |
|   |  - Tracks activity    |      |    at interval boundary   |   |
|   |  - Supplies eligible  |      |  - Any address can call   |   |
|   |    wallet list        |      |                           |   |
|   +----------------------+      +---------------------------+   |
|                                                                  |
|   +----------------------+                                      |
|   |  Analytics Dashboard  |                                      |
|   |                      |                                      |
|   |  - Cycle history      |                                      |
|   |  - Outcome freq.      |                                      |
|   |  - Distribution map   |                                      |
|   |  - BONK reserve level |                                      |
|   +----------------------+                                       |
+------------------------------------------------------------------+
```

---

## DATA FLOW: STANDARD TRANSFER

```
User calls transfer(to, amount)
        |
        v
_update() hook fires
        |
        +-- record lastActivityBlock[from]
        +-- record lastActivityBlock[to]
        |
        v
fee = amount * TRANSACTION_FEE_BPS / 10000
netAmount = amount - fee
        |
        v
super._update(from, to, netAmount)        // net transfer
super._update(from, address(this), fee)   // fee to contract
        |
        v
accumulatedFees += fee
```

---

## DATA FLOW: QUANTUM CYCLE EXECUTION

```
Caller invokes quantumCycle()
        |
        v
require(block.timestamp >= lastCycleTime + CYCLE_INTERVAL)
        |
        v
feePool = accumulatedFees
accumulatedFees = 0
        |
        v
entropy = keccak256(blockhash(N-1), timestamp, internalSeed)
entropyValue = uint16(entropy % 10000)
        |
        v
effectiveWeights = _computeEffectiveWeights()
  (adjusts base weights by BONK reserve level)
        |
        v
outcome = _selectOutcome(entropyValue, effectiveWeights)
        |
        +---------+-----------+-----------+
        |         |           |           |
      [0]       [1]         [2]
  DISTRIBUTE  BUYBACK     BURN
        |         |           |
        v         v           v
  select 50   swap fees   burn tokens
  wallets     for tokens  from contract
  distribute              balance
  equally
        |         |           |
        +---------+-----------+
                  |
                  v
internalSeed = keccak256(seed, entropy, outcomeId, blockNumber, cycleId)
lastCycleTime = block.timestamp
cycleId++
                  |
                  v
emit CycleExecuted(...)
```

---

## ENTROPY DERIVATION DETAIL

```
INPUTS:
  A = blockhash(block.number - 1)     [32 bytes, determined by miners]
  B = block.timestamp                  [uint256, seconds since epoch]
  C = internalSeed                     [bytes32, updated each cycle]

COMPUTATION:
  entropy      = keccak256(A, B, C)   [256-bit hash]
  entropyValue = entropy % 10000      [uint16 in [0, 9999]]

OUTCOME BANDS:
  [0,    3999] -> DISTRIBUTE   (40%)
  [4000, 7999] -> BUYBACK      (40%)
  [8000, 9999] -> BURN         (20%)

SEED UPDATE:
  newSeed = keccak256(C, entropy, outcomeId, block.number, cycleId)
```

---

## ELIGIBILITY ORACLE DESIGN

The contract cannot enumerate all token holders on-chain. This is a fundamental
constraint of EVM architecture. To resolve this, the eligibility oracle operates
as follows:

1. Index all Transfer events from contract deployment
2. Maintain a live balance map: address -> balance
3. Maintain a live activity map: address -> lastBlockSeen
4. At cycle execution time, compute eligible set:
   - balance >= MIN_HOLD_THRESHOLD
   - lastBlock >= currentBlock - ACTIVITY_WINDOW
   - not in exclusion list
5. Supply the eligible address array as calldata to the cycle execution call

The oracle is permissionless. Anyone can run one. The contract validates eligibility
for each supplied address at execution time, rejecting ineligible entries.

```
Off-chain Oracle                          Contract
      |                                       |
      | monitors Transfer events              |
      | builds eligible[] list                |
      |                                       |
      +-- calls quantumCycle(eligible[]) ---->|
                                              |
                                              | validates each address
                                              | filters ineligible
                                              | runs selection
                                              | distributes
```

---

## BONK ENTROPY LAYER

```
BONK Reserve Level         Effective Weights
                           [DIST, BUYBACK, BURN]
      0 BONK               [4000,  4000,  2000]  (base)
  25,000 BONK              [4100,  3950,  1950]
  50,000 BONK              [4200,  3900,  1900]
 100,000 BONK              [4400,  3800,  1800]
 MAX_CAP BONK              [4000 + MAX_MOD, ...]
```

The modifier is bounded by MAX_BONK_MODIFIER, preventing the BONK layer from
dominating the weight structure.

---

## SECURITY CONSIDERATIONS

### Miner/Validator Entropy Attack Surface

blockhash and timestamp are theoretically manipulable by block producers.
The practical attack surface is limited:

- Timestamp grinding: shifting by ~10 seconds affects entropy but cycle
  interval is 10 minutes; the gain is minimal
- blockhash withholding: a validator could withhold a block to remine it
  with a more favorable hash, but would forfeit block rewards; the maximum
  economic gain from a single favorable cycle outcome must exceed the cost
  of the withheld block for this to be rational
- The internalSeed adds a stateful component that makes multi-cycle
  prediction compounding in difficulty

This entropy design is suitable for the probabilistic token mechanic described.
It is not suitable for high-value randomness applications (e.g., lottery).

### Reentrancy

All external calls in outcome execution follow checks-effects-interactions.
The ReentrancyGuard is applied to quantumCycle().

### Fee Drain

accumulatedFees is zeroed at the start of cycle execution before any outcome
logic runs. This prevents a scenario where a re-entered cycle could double-spend
the fee pool.

### Eligibility Oracle Trust

The oracle supplies the candidate list. The contract validates each candidate.
A malicious oracle could supply an empty list or a list of ineligible addresses,
causing the distribution to fail or revert. This would delay distribution by
one cycle. It cannot cause fund loss or incorrect outcomes.

---

*Architecture version 0.1.0*
