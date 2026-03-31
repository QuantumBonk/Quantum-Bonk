// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IQuantumBonk
 * @notice External interface for the Quantum Bonk protocol.
 */
interface IQuantumBonk {

    enum Outcome { DISTRIBUTE, BUYBACK, BURN }

    event CycleExecuted(
        uint256 indexed cycleId,
        bytes32 entropyHash,
        uint16  entropyValue,
        uint8   outcomeId,
        uint256 feePool
    );

    event BuybackExecuted(uint256 indexed cycleId, uint256 feePool, uint256 tokensBought);
    event BurnExecuted(uint256 indexed cycleId, uint256 feePool, uint256 tokensBurned);
    event DistributionExecuted(
        uint256 indexed cycleId,
        uint256 feePool,
        uint256 perWallet,
        address[50] recipients
    );

    function quantumCycle() external;

    function getCycleState() external view returns (
        uint256 currentCycleId,
        uint256 nextCycleTime,
        uint256 currentFeePool,
        uint256 bonkReserve,
        bytes32 currentSeed
    );

    function isEligible(address account) external view returns (bool);

    function timeUntilNextCycle() external view returns (uint256);

    function verifyOutcome(
        bytes32 blockHash,
        uint256 timestamp,
        bytes32 seed,
        uint8   claimedOutcome
    ) external view returns (bool valid, uint16 entropyValue);

    function getEffectiveWeights() external view returns (uint16[3] memory);

    function getCumulativeStats() external view returns (
        uint256 burned,
        uint256 boughtBack,
        uint256 distributed,
        uint256 cycles
    );
}
