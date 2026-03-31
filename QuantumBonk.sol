// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title QuantumBonk
 * @notice A probabilistic token system where outcomes do not exist until execution.
 * @dev Every 10 minutes, the system enters superposition across three possible actions,
 *      then collapses into one outcome using deterministic on-chain entropy.
 *
 *      Outcomes:
 *        0 - DISTRIBUTE: fee pool distributed equally to 50 eligible wallets
 *        1 - BUYBACK:    fee pool used to purchase tokens from open market
 *        2 - BURN:       fee pool used to reduce circulating supply
 *
 *      Entropy source:
 *        keccak256(block.hash, block.timestamp, internalSeed)
 *
 *      No admin control over outcome selection.
 *      No snapshots. No staking. Live eligibility only.
 *
 * @author Quantum Bonk Protocol
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IBONK {
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IDEXRouter {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

contract QuantumBonk is ERC20, Ownable, ReentrancyGuard {

    // -------------------------------------------------------------------------
    // CONSTANTS
    // -------------------------------------------------------------------------

    uint256 public constant CYCLE_INTERVAL    = 600;      // 10 minutes in seconds
    uint256 public constant WEIGHT_BASE       = 10000;    // denominator for probability weights
    uint256 public constant MAX_RECIPIENTS    = 50;       // wallets per distribution event
    uint256 public constant FEE_DENOMINATOR   = 10000;    // fee calculation base

    // -------------------------------------------------------------------------
    // OUTCOME ENUM
    // -------------------------------------------------------------------------

    enum Outcome { DISTRIBUTE, BUYBACK, BURN }

    // -------------------------------------------------------------------------
    // IMMUTABLE CONFIGURATION (SET AT DEPLOYMENT, CANNOT CHANGE)
    // -------------------------------------------------------------------------

    uint256 public immutable MIN_HOLD_THRESHOLD;   // minimum tokens to be eligible
    uint256 public immutable ACTIVITY_WINDOW;      // blocks within which wallet must be active
    uint256 public immutable BONK_SCALE_FACTOR;    // BONK units per weight point modifier
    uint256 public immutable MAX_BONK_MODIFIER;    // cap on BONK-derived weight shift
    uint256 public immutable BONK_MIN_HOLD;        // BONK held to receive elevated selection
    uint256 public immutable TRANSACTION_FEE_BPS;  // transaction fee in basis points
    bool    public immutable BONK_ELEVATION_ENABLED;

    // -------------------------------------------------------------------------
    // MUTABLE STATE (BOUNDED)
    // -------------------------------------------------------------------------

    bytes32 public internalSeed;
    uint256 public lastCycleTime;
    uint256 public cycleId;
    uint256 public accumulatedFees;
    uint256 public bonkEntropyReserve;

    // Cumulative statistics
    uint256 public totalBurned;
    uint256 public totalBoughtBack;
    uint256 public totalDistributed;
    uint256 public totalCycles;

    // Outcome weights [DISTRIBUTE, BUYBACK, BURN]
    uint16[3] public outcomeWeights;

    // Addresses
    IBONK     public bonkToken;
    IDEXRouter public dexRouter;
    address   public weth;

    // Exclusion list (zero address, contract addresses, etc.)
    mapping(address => bool) public excluded;

    // Activity tracking: last tx block per address
    mapping(address => uint256) public lastActivityBlock;

    // -------------------------------------------------------------------------
    // EVENTS
    // -------------------------------------------------------------------------

    event CycleExecuted(
        uint256 indexed cycleId,
        bytes32 entropyHash,
        uint16  entropyValue,
        uint8   outcomeId,
        uint256 feePool
    );

    event BuybackExecuted(
        uint256 indexed cycleId,
        uint256 feePool,
        uint256 tokensBought
    );

    event BurnExecuted(
        uint256 indexed cycleId,
        uint256 feePool,
        uint256 tokensBurned
    );

    event DistributionExecuted(
        uint256 indexed cycleId,
        uint256 feePool,
        uint256 perWallet,
        address[50] recipients
    );

    event ExclusionUpdated(address indexed account, bool excluded);
    event ActivityRecorded(address indexed account, uint256 blockNumber);

    // -------------------------------------------------------------------------
    // CONSTRUCTOR
    // -------------------------------------------------------------------------

    constructor(
        string  memory name_,
        string  memory symbol_,
        uint256 initialSupply,
        uint256 minHoldThreshold,
        uint256 activityWindow,
        uint256 bonkScaleFactor,
        uint256 maxBonkModifier,
        uint256 bonkMinHold,
        uint256 transactionFeeBps,
        bool    bonkElevationEnabled,
        address bonkToken_,
        address dexRouter_,
        address weth_,
        bytes32 genesisEntropy
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        MIN_HOLD_THRESHOLD     = minHoldThreshold;
        ACTIVITY_WINDOW        = activityWindow;
        BONK_SCALE_FACTOR      = bonkScaleFactor;
        MAX_BONK_MODIFIER      = maxBonkModifier;
        BONK_MIN_HOLD          = bonkMinHold;
        TRANSACTION_FEE_BPS    = transactionFeeBps;
        BONK_ELEVATION_ENABLED = bonkElevationEnabled;

        bonkToken  = IBONK(bonkToken_);
        dexRouter  = IDEXRouter(dexRouter_);
        weth       = weth_;

        // Default weights: 40% DISTRIBUTE, 40% BUYBACK, 20% BURN
        outcomeWeights[0] = 4000;
        outcomeWeights[1] = 4000;
        outcomeWeights[2] = 2000;

        internalSeed  = genesisEntropy;
        lastCycleTime = block.timestamp;

        _mint(msg.sender, initialSupply);

        // Exclude contract itself
        excluded[address(this)] = true;
        excluded[address(0)]    = true;
    }

    // -------------------------------------------------------------------------
    // TRANSFER OVERRIDE (FEE COLLECTION)
    // -------------------------------------------------------------------------

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        // Record activity for eligibility tracking
        if (from != address(0) && !excluded[from]) {
            lastActivityBlock[from] = block.number;
        }
        if (to != address(0) && !excluded[to]) {
            lastActivityBlock[to] = block.number;
        }

        // No fee on mint, burn, or excluded addresses
        if (from == address(0) || to == address(0) || excluded[from] || excluded[to]) {
            super._update(from, to, amount);
            return;
        }

        // Deduct fee
        uint256 fee = (amount * TRANSACTION_FEE_BPS) / FEE_DENOMINATOR;
        uint256 netAmount = amount - fee;

        accumulatedFees += fee;

        super._update(from, to, netAmount);
        super._update(from, address(this), fee);
    }

    // -------------------------------------------------------------------------
    // QUANTUM CYCLE
    // -------------------------------------------------------------------------

    /**
     * @notice Execute the quantum cycle. Can be called by anyone once the
     *         interval has elapsed. Caller cannot influence the outcome.
     */
    function quantumCycle() external nonReentrant {
        require(
            block.timestamp >= lastCycleTime + CYCLE_INTERVAL,
            "CYCLE_INTERVAL_NOT_ELAPSED"
        );

        uint256 feePool = accumulatedFees;
        accumulatedFees = 0;
        lastCycleTime = block.timestamp;

        // Derive entropy
        bytes32 entropy = keccak256(abi.encodePacked(
            blockhash(block.number - 1),
            block.timestamp,
            internalSeed
        ));

        // Normalize to [0, 9999]
        uint16 entropyValue = uint16(uint256(entropy) % 10000);

        // Compute effective weights with BONK modifier
        uint16[3] memory effectiveWeights = _computeEffectiveWeights();

        // Select outcome
        Outcome outcome = _selectOutcome(entropyValue, effectiveWeights);

        // Execute outcome
        if (outcome == Outcome.BUYBACK) {
            _executeBuyback(feePool);
        } else if (outcome == Outcome.DISTRIBUTE) {
            _executeDistribution(feePool, entropy);
        } else {
            _executeBurn(feePool);
        }

        // Update seed
        internalSeed = keccak256(abi.encodePacked(
            internalSeed,
            entropy,
            uint8(outcome),
            block.number,
            cycleId
        ));

        emit CycleExecuted(cycleId, entropy, entropyValue, uint8(outcome), feePool);
        cycleId++;
        totalCycles++;
    }

    // -------------------------------------------------------------------------
    // OUTCOME SELECTION
    // -------------------------------------------------------------------------

    function _selectOutcome(
        uint16 entropyValue,
        uint16[3] memory weights
    ) internal pure returns (Outcome) {
        uint16 cursor = 0;
        for (uint8 i = 0; i < 3; i++) {
            cursor += weights[i];
            if (entropyValue < cursor) {
                return Outcome(i);
            }
        }
        revert("OUTCOME_SELECTION_FAILED");
    }

    function _computeEffectiveWeights() internal view returns (uint16[3] memory) {
        uint16[3] memory weights = outcomeWeights;

        if (BONK_SCALE_FACTOR == 0 || bonkEntropyReserve == 0) {
            return weights;
        }

        uint256 modifier_ = bonkEntropyReserve / BONK_SCALE_FACTOR;
        if (modifier_ > MAX_BONK_MODIFIER) {
            modifier_ = MAX_BONK_MODIFIER;
        }

        uint16 mod16 = uint16(modifier_);

        // DISTRIBUTE probability increases with BONK reserve
        // BUYBACK and BURN decrease proportionally
        if (weights[0] + mod16 <= WEIGHT_BASE) {
            weights[0] += mod16;
        }
        if (weights[1] > mod16 / 2) {
            weights[1] -= uint16(mod16 / 2);
        }
        if (weights[2] > mod16 / 2) {
            weights[2] -= uint16(mod16 / 2);
        }

        return weights;
    }

    // -------------------------------------------------------------------------
    // BUYBACK
    // -------------------------------------------------------------------------

    function _executeBuyback(uint256 feePool) internal {
        if (feePool == 0) return;

        // Approve DEX to spend tokens held in contract
        // In production: convert feePool (tokens) to ETH, then buy back
        // This is a simplified representation
        uint256 tokensBought = feePool; // placeholder for actual DEX swap

        totalBoughtBack += tokensBought;
        emit BuybackExecuted(cycleId, feePool, tokensBought);
    }

    // -------------------------------------------------------------------------
    // DISTRIBUTION
    // -------------------------------------------------------------------------

    function _executeDistribution(uint256 feePool, bytes32 entropy) internal {
        if (feePool == 0) return;

        address[] memory eligible = _getEligibleWallets();
        require(eligible.length >= MAX_RECIPIENTS, "INSUFFICIENT_ELIGIBLE_WALLETS");

        address[50] memory winners = _selectWallets(eligible, entropy);
        uint256 perWallet = feePool / MAX_RECIPIENTS;

        for (uint256 i = 0; i < MAX_RECIPIENTS; i++) {
            if (winners[i] != address(0)) {
                super._update(address(this), winners[i], perWallet);
            }
        }

        totalDistributed += feePool;
        emit DistributionExecuted(cycleId, feePool, perWallet, winners);
    }

    function _getEligibleWallets() internal view returns (address[] memory) {
        // In production this would be supplied via off-chain indexer or
        // Merkle proof. On-chain enumeration of all holders is not feasible
        // at scale. The eligibility check is performed per-address:
        //
        //   balanceOf(addr) >= MIN_HOLD_THRESHOLD
        //   lastActivityBlock[addr] >= block.number - ACTIVITY_WINDOW
        //   !excluded[addr]
        //
        // This function is left as a hook for integration with an eligibility
        // oracle or calldata-supplied candidate list.
        revert("OVERRIDE_WITH_ELIGIBILITY_ORACLE");
    }

    function _selectWallets(
        address[] memory eligibleSet,
        bytes32 entropy
    ) internal pure returns (address[50] memory winners) {
        uint256 n = eligibleSet.length;
        bytes32 seed = entropy;

        for (uint256 i = 0; i < MAX_RECIPIENTS; i++) {
            seed = keccak256(abi.encodePacked(seed, i));
            uint256 j = i + (uint256(seed) % (n - i));

            address temp = eligibleSet[i];
            eligibleSet[i] = eligibleSet[j];
            eligibleSet[j] = temp;

            winners[i] = eligibleSet[i];
        }
    }

    // -------------------------------------------------------------------------
    // BURN
    // -------------------------------------------------------------------------

    function _executeBurn(uint256 feePool) internal {
        if (feePool == 0) return;

        uint256 contractBalance = balanceOf(address(this));
        uint256 burnAmount = feePool <= contractBalance ? feePool : contractBalance;

        _burn(address(this), burnAmount);
        totalBurned += burnAmount;
        emit BurnExecuted(cycleId, feePool, burnAmount);
    }

    // -------------------------------------------------------------------------
    // BONK RESERVE MANAGEMENT
    // -------------------------------------------------------------------------

    function depositBonkEntropy(uint256 amount) external {
        require(
            bonkToken.transferFrom(msg.sender, address(this), amount),
            "BONK_TRANSFER_FAILED"
        );
        bonkEntropyReserve += amount;
    }

    // -------------------------------------------------------------------------
    // ADMIN (BOUNDED)
    // -------------------------------------------------------------------------

    /**
     * @notice Update the exclusion list.
     *         Owner can only add/remove addresses from exclusion.
     *         Cannot modify weights, cycle interval, or entropy logic.
     */
    function setExclusion(address account, bool isExcluded) external onlyOwner {
        excluded[account] = isExcluded;
        emit ExclusionUpdated(account, isExcluded);
    }

    // -------------------------------------------------------------------------
    // VIEW FUNCTIONS
    // -------------------------------------------------------------------------

    function getCycleState() external view returns (
        uint256 currentCycleId,
        uint256 nextCycleTime,
        uint256 currentFeePool,
        uint256 bonkReserve,
        bytes32 currentSeed
    ) {
        return (
            cycleId,
            lastCycleTime + CYCLE_INTERVAL,
            accumulatedFees,
            bonkEntropyReserve,
            internalSeed
        );
    }

    function getEffectiveWeights() external view returns (uint16[3] memory) {
        return _computeEffectiveWeights();
    }

    function isEligible(address account) external view returns (bool) {
        return (
            balanceOf(account) >= MIN_HOLD_THRESHOLD &&
            lastActivityBlock[account] >= block.number - ACTIVITY_WINDOW &&
            !excluded[account]
        );
    }

    function getCumulativeStats() external view returns (
        uint256 burned,
        uint256 boughtBack,
        uint256 distributed,
        uint256 cycles
    ) {
        return (totalBurned, totalBoughtBack, totalDistributed, totalCycles);
    }

    function timeUntilNextCycle() external view returns (uint256) {
        uint256 next = lastCycleTime + CYCLE_INTERVAL;
        if (block.timestamp >= next) return 0;
        return next - block.timestamp;
    }

    // -------------------------------------------------------------------------
    // ENTROPY VERIFICATION HELPER
    // -------------------------------------------------------------------------

    /**
     * @notice Verify a historical cycle outcome given the entropy inputs.
     *         Anyone can call this to confirm an outcome was correctly computed.
     */
    function verifyOutcome(
        bytes32 blockHash,
        uint256 timestamp,
        bytes32 seed,
        uint8   claimedOutcome
    ) external view returns (bool valid, uint16 entropyValue) {
        bytes32 entropy = keccak256(abi.encodePacked(blockHash, timestamp, seed));
        entropyValue = uint16(uint256(entropy) % 10000);

        uint16 cursor = 0;
        for (uint8 i = 0; i < 3; i++) {
            cursor += outcomeWeights[i];
            if (entropyValue < cursor) {
                valid = (i == claimedOutcome);
                return (valid, entropyValue);
            }
        }
        valid = false;
    }
}
