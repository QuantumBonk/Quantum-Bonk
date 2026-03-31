/**
 * verifyOutcome.js
 *
 * Verifies a historical quantum cycle outcome using publicly available
 * block data and the emitted event parameters.
 *
 * Given a cycle event log, recomputes entropy from source inputs and
 * confirms the declared outcome is correct.
 *
 * Usage:
 *   node verifyOutcome.js <blockHash> <timestamp> <seed> <claimedOutcome>
 *
 * Example:
 *   node verifyOutcome.js \
 *     0xabc123... \
 *     1700600000 \
 *     0xdef456... \
 *     DISTRIBUTE
 */

"use strict";

const crypto = require("crypto");

const OUTCOMES = ["DISTRIBUTE", "BUYBACK", "BURN"];
const BASE_WEIGHTS = [4000, 4000, 2000];
const WEIGHT_BASE  = 10000;

function recomputeEntropy(blockHash, timestamp, seed) {
  const input = Buffer.concat([
    Buffer.from(blockHash.replace("0x", ""), "hex"),
    Buffer.alloc(8).fill(0),
    Buffer.from(seed.replace("0x", ""), "hex"),
  ]);
  const hash  = crypto.createHash("sha256").update(input).digest("hex");
  const value = parseInt(hash.slice(0, 8), 16);
  return {
    entropyHash:  "0x" + hash,
    entropyValue: value % WEIGHT_BASE,
  };
}

function resolveOutcome(entropyValue, weights) {
  let cursor = 0;
  for (let i = 0; i < weights.length; i++) {
    cursor += weights[i];
    if (entropyValue < cursor) return OUTCOMES[i];
  }
  return null;
}

function verify(blockHash, timestamp, seed, claimedOutcome) {
  const { entropyHash, entropyValue } = recomputeEntropy(blockHash, timestamp, seed);
  const resolvedOutcome = resolveOutcome(entropyValue, BASE_WEIGHTS);

  const valid = resolvedOutcome === claimedOutcome.toUpperCase();

  console.log("\n" + "=".repeat(50));
  console.log("  QUANTUM BONK - OUTCOME VERIFICATION");
  console.log("=".repeat(50));
  console.log(`  Block Hash:       ${blockHash.slice(0, 18)}...`);
  console.log(`  Timestamp:        ${timestamp}`);
  console.log(`  Seed (prior):     ${seed.slice(0, 18)}...`);
  console.log(`  Entropy Hash:     ${entropyHash.slice(0, 18)}...`);
  console.log(`  Entropy Value:    ${entropyValue} / ${WEIGHT_BASE - 1}`);
  console.log("");

  let cursor = 0;
  for (let i = 0; i < BASE_WEIGHTS.length; i++) {
    const lo  = cursor;
    const hi  = cursor + BASE_WEIGHTS[i] - 1;
    const hit = entropyValue >= lo && entropyValue <= hi ? " <-- MATCH" : "";
    console.log(`  [${String(lo).padStart(4)}, ${String(hi).padStart(4)}]  ${OUTCOMES[i].padEnd(12)}${hit}`);
    cursor += BASE_WEIGHTS[i];
  }

  console.log("");
  console.log(`  Resolved Outcome: ${resolvedOutcome}`);
  console.log(`  Claimed Outcome:  ${claimedOutcome.toUpperCase()}`);
  console.log(`  Verification:     ${valid ? "PASS" : "FAIL"}`);
  console.log("=".repeat(50) + "\n");

  return valid;
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

const args = process.argv.slice(2);

if (args.length < 4) {
  // Run a demo verification with synthetic data
  console.log("\n  No arguments supplied. Running demo verification.\n");

  const demoBlockHash = "0x" + crypto.randomBytes(32).toString("hex");
  const demoTimestamp = 1700600000;
  const demoSeed      = "0x" + crypto.randomBytes(32).toString("hex");

  // Compute what the outcome should be so we can claim it correctly
  const { entropyValue } = recomputeEntropy(demoBlockHash, demoTimestamp, demoSeed);
  const correctOutcome   = resolveOutcome(entropyValue, BASE_WEIGHTS);

  verify(demoBlockHash, demoTimestamp, demoSeed, correctOutcome);

  // Also verify an incorrect claim to show FAIL output
  const wrongOutcomes = OUTCOMES.filter(o => o !== correctOutcome);
  console.log("  Verifying incorrect claim:\n");
  verify(demoBlockHash, demoTimestamp, demoSeed, wrongOutcomes[0]);

} else {
  const [blockHash, timestamp, seed, claimedOutcome] = args;
  verify(blockHash, parseInt(timestamp), seed, claimedOutcome);
}
