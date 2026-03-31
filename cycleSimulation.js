/**
 * cycleSimulation.js
 *
 * Simulates N quantum cycles and reports outcome distribution,
 * streak analysis, and BONK modifier effects.
 *
 * Usage:
 *   node cycleSimulation.js [cycles] [seed]
 *
 * Examples:
 *   node cycleSimulation.js
 *   node cycleSimulation.js 50000
 *   node cycleSimulation.js 10000 my_custom_seed
 */

"use strict";

const crypto = require("crypto");

// ---------------------------------------------------------------------------
// CONFIGURATION
// ---------------------------------------------------------------------------

const CONFIG = {
  BASE_WEIGHTS: {
    DISTRIBUTE: 4000,
    BUYBACK: 4000,
    BURN: 2000,
  },
  WEIGHT_BASE: 10000,
  BONK_SCALE_FACTOR: 50000,   // BONK units per weight point
  MAX_BONK_MODIFIER: 500,     // max shift in weight units
  BONK_DEPOSIT_PER_CYCLE: 10000, // simulated BONK deposited per cycle
  BONK_ENABLED: true,
};

// ---------------------------------------------------------------------------
// ENTROPY
// ---------------------------------------------------------------------------

/**
 * Derive a deterministic entropy value from block data and seed.
 * Mirrors the Solidity implementation.
 *
 * @param {string} blockHash  - 64-char hex string
 * @param {number} timestamp  - unix timestamp
 * @param {string} seed       - current internal seed (hex string)
 * @returns {number}          - integer in [0, 9999]
 */
function deriveEntropy(blockHash, timestamp, seed) {
  const input = Buffer.concat([
    Buffer.from(blockHash.replace("0x", ""), "hex"),
    Buffer.alloc(8).fill(0), // simplified timestamp encoding
    Buffer.from(seed.replace("0x", ""), "hex"),
  ]);

  const hash = crypto.createHash("sha256").update(input).digest("hex");
  const value = parseInt(hash.slice(0, 8), 16);
  return value % CONFIG.WEIGHT_BASE;
}

/**
 * Update the internal seed after a cycle completes.
 */
function updateSeed(seed, entropy, outcomeIndex, cycleId) {
  const input = `${seed}${entropy}${outcomeIndex}${cycleId}`;
  return "0x" + crypto.createHash("sha256").update(input).digest("hex");
}

// ---------------------------------------------------------------------------
// WEIGHT COMPUTATION
// ---------------------------------------------------------------------------

/**
 * Compute effective weights given current BONK reserve level.
 */
function computeEffectiveWeights(bonkReserve) {
  if (!CONFIG.BONK_ENABLED || bonkReserve === 0) {
    return { ...CONFIG.BASE_WEIGHTS };
  }

  let modifier = Math.floor(bonkReserve / CONFIG.BONK_SCALE_FACTOR);
  modifier = Math.min(modifier, CONFIG.MAX_BONK_MODIFIER);

  const half = Math.floor(modifier / 2);

  return {
    DISTRIBUTE: CONFIG.BASE_WEIGHTS.DISTRIBUTE + modifier,
    BUYBACK:    CONFIG.BASE_WEIGHTS.BUYBACK - half,
    BURN:       CONFIG.BASE_WEIGHTS.BURN - half,
  };
}

// ---------------------------------------------------------------------------
// OUTCOME SELECTION
// ---------------------------------------------------------------------------

const OUTCOMES = ["DISTRIBUTE", "BUYBACK", "BURN"];

/**
 * Select an outcome given an entropy value and effective weights.
 *
 * @param {number} entropyValue - integer in [0, 9999]
 * @param {object} weights      - { DISTRIBUTE, BUYBACK, BURN }
 * @returns {string}            - outcome name
 */
function selectOutcome(entropyValue, weights) {
  let cursor = 0;
  for (const outcome of OUTCOMES) {
    cursor += weights[outcome];
    if (entropyValue < cursor) {
      return outcome;
    }
  }
  throw new Error("Outcome selection failed: weights do not sum to WEIGHT_BASE");
}

// ---------------------------------------------------------------------------
// SIMULATION
// ---------------------------------------------------------------------------

/**
 * Run a full simulation of N cycles.
 *
 * @param {number} n        - number of cycles to simulate
 * @param {string} initSeed - genesis seed hex string
 * @returns {object}        - simulation results
 */
function simulateCycles(n, initSeed) {
  let seed        = initSeed;
  let bonkReserve = 0;

  const counts = { DISTRIBUTE: 0, BUYBACK: 0, BURN: 0 };
  const streaks = [];
  const entropyValues = [];
  const weightHistory = [];

  let currentStreak = { outcome: null, length: 0 };
  let maxStreak = { outcome: null, length: 0 };

  for (let i = 0; i < n; i++) {
    // Simulate block data
    const blockHash   = crypto.randomBytes(32).toString("hex");
    const timestamp   = 1700000000 + i * 600;

    // Simulate BONK deposit each cycle
    bonkReserve += CONFIG.BONK_DEPOSIT_PER_CYCLE;

    const effectiveWeights = computeEffectiveWeights(bonkReserve);
    const entropyValue     = deriveEntropy(blockHash, timestamp, seed);
    const outcome          = selectOutcome(entropyValue, effectiveWeights);

    counts[outcome]++;
    entropyValues.push(entropyValue);

    if (i % Math.floor(n / 10) === 0) {
      weightHistory.push({ cycle: i, weights: { ...effectiveWeights }, bonkReserve });
    }

    // Streak tracking
    if (outcome === currentStreak.outcome) {
      currentStreak.length++;
    } else {
      if (currentStreak.outcome !== null) {
        streaks.push({ ...currentStreak });
        if (currentStreak.length > maxStreak.length) {
          maxStreak = { ...currentStreak };
        }
      }
      currentStreak = { outcome, length: 1 };
    }

    // Update seed
    seed = updateSeed(seed, entropyValue, OUTCOMES.indexOf(outcome), i);
  }

  // Push final streak
  if (currentStreak.outcome !== null) {
    streaks.push({ ...currentStreak });
    if (currentStreak.length > maxStreak.length) {
      maxStreak = { ...currentStreak };
    }
  }

  // Compute streak statistics per outcome
  const streakStats = {};
  for (const o of OUTCOMES) {
    const outcomeStreaks = streaks.filter(s => s.outcome === o).map(s => s.length);
    streakStats[o] = {
      maxStreak:  outcomeStreaks.length > 0 ? Math.max(...outcomeStreaks) : 0,
      meanStreak: outcomeStreaks.length > 0
        ? (outcomeStreaks.reduce((a, b) => a + b, 0) / outcomeStreaks.length).toFixed(2)
        : "0.00",
      totalRuns:  outcomeStreaks.length,
    };
  }

  // Entropy distribution (percentile buckets)
  const buckets = new Array(10).fill(0);
  for (const v of entropyValues) {
    buckets[Math.floor(v / 1000)]++;
  }

  return {
    totalCycles: n,
    counts,
    frequencies: {
      DISTRIBUTE: (counts.DISTRIBUTE / n * 100).toFixed(4) + "%",
      BUYBACK:    (counts.BUYBACK    / n * 100).toFixed(4) + "%",
      BURN:       (counts.BURN       / n * 100).toFixed(4) + "%",
    },
    maxStreak,
    streakStats,
    entropyBuckets: buckets,
    weightHistory,
    finalSeed: seed,
    finalBonkReserve: bonkReserve,
  };
}

// ---------------------------------------------------------------------------
// OUTPUT
// ---------------------------------------------------------------------------

function printResults(results) {
  const bar = (label, count, total, width = 40) => {
    const filled = Math.round(count / total * width);
    const empty  = width - filled;
    return `${"#".repeat(filled)}${".".repeat(empty)}`;
  };

  console.log("\n" + "=".repeat(60));
  console.log("  QUANTUM BONK - CYCLE SIMULATION RESULTS");
  console.log("=".repeat(60));

  console.log(`\n  Total Cycles Simulated: ${results.totalCycles.toLocaleString()}`);
  console.log(`  Final Seed:             ${results.finalSeed.slice(0, 18)}...`);
  console.log(`  Final BONK Reserve:     ${results.finalBonkReserve.toLocaleString()}`);

  console.log("\n  OUTCOME DISTRIBUTION");
  console.log("  " + "-".repeat(56));

  for (const outcome of OUTCOMES) {
    const count = results.counts[outcome];
    const freq  = results.frequencies[outcome];
    const b     = bar(outcome, count, results.totalCycles);
    console.log(`  ${outcome.padEnd(12)} ${freq.padStart(8)}  [${b}]  ${count.toLocaleString()}`);
  }

  console.log("\n  STREAK ANALYSIS");
  console.log("  " + "-".repeat(56));

  for (const outcome of OUTCOMES) {
    const s = results.streakStats[outcome];
    console.log(
      `  ${outcome.padEnd(12)} max=${String(s.maxStreak).padStart(4)}  ` +
      `mean=${String(s.meanStreak).padStart(5)}  runs=${s.totalRuns.toLocaleString()}`
    );
  }

  console.log(`\n  Longest single streak: ${results.maxStreak.length}x ${results.maxStreak.outcome}`);

  console.log("\n  ENTROPY VALUE DISTRIBUTION (1000-unit buckets)");
  console.log("  " + "-".repeat(56));

  const maxBucket = Math.max(...results.entropyBuckets);
  results.entropyBuckets.forEach((count, i) => {
    const range  = `${i * 1000}-${(i + 1) * 1000 - 1}`.padEnd(10);
    const filled = Math.round(count / maxBucket * 30);
    const b      = "#".repeat(filled);
    const pct    = (count / results.totalCycles * 100).toFixed(2);
    console.log(`  [${range}]  ${b.padEnd(30)}  ${pct}%`);
  });

  if (results.weightHistory.length > 0) {
    console.log("\n  BONK WEIGHT MODIFIER HISTORY");
    console.log("  " + "-".repeat(56));
    console.log("  Cycle       DISTRIBUTE  BUYBACK  BURN    BONK Reserve");
    for (const entry of results.weightHistory) {
      const w = entry.weights;
      console.log(
        `  ${String(entry.cycle).padEnd(12)}` +
        `${String(w.DISTRIBUTE).padEnd(12)}` +
        `${String(w.BUYBACK).padEnd(9)}` +
        `${String(w.BURN).padEnd(8)}` +
        `${entry.bonkReserve.toLocaleString()}`
      );
    }
  }

  console.log("\n" + "=".repeat(60) + "\n");
}

// ---------------------------------------------------------------------------
// ENTRY POINT
// ---------------------------------------------------------------------------

const args       = process.argv.slice(2);
const N          = parseInt(args[0]) || 10000;
const customSeed = args[1];
const INIT_SEED  = customSeed
  ? "0x" + crypto.createHash("sha256").update(customSeed).digest("hex")
  : "0x" + crypto.randomBytes(32).toString("hex");

console.log(`\n  Starting simulation: ${N.toLocaleString()} cycles`);
console.log(`  Genesis seed: ${INIT_SEED.slice(0, 18)}...`);

const results = simulateCycles(N, INIT_SEED);
printResults(results);
