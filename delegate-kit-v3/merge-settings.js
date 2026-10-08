#!/usr/bin/env node
// Merge settings.snippet.json into a Claude Code settings.json safely.
//   node merge-settings.js            -> merge into ~/.claude/settings.json (or $CLAUDE_HOME/settings.json)
//   node merge-settings.js --dry-run  -> show what would be added, change nothing
// Rules: backs up the existing file first; never removes or overwrites existing entries;
// permissions.allow / permissions.deny are unioned; env keys are added only if absent;
// every other key is left exactly as it was. Safe to run repeatedly.
const fs = require("fs");
const path = require("path");
const os = require("os");

const dry = process.argv.includes("--dry-run");
const root = process.env.CLAUDE_HOME || path.join(os.homedir(), ".claude");
const target = path.join(root, "settings.json");
const snippetPath = path.join(__dirname, "settings.snippet.json");

function readJson(p, label) {
  try {
    return JSON.parse(fs.readFileSync(p, "utf8"));
  } catch (e) {
    console.error(`ERROR: cannot parse ${label} (${p}): ${e.message}`);
    console.error("Nothing was changed.");
    process.exit(1);
  }
}

const snippet = readJson(snippetPath, "snippet");
const exists = fs.existsSync(target);
const current = exists ? readJson(target, "current settings") : {};
if (typeof current !== "object" || current === null || Array.isArray(current)) {
  console.error("ERROR: settings.json is not a JSON object. Nothing was changed.");
  process.exit(1);
}

const merged = JSON.parse(JSON.stringify(current));
const added = { allow: [], deny: [], env: [] };

merged.permissions = merged.permissions || {};
for (const key of ["allow", "deny"]) {
  const have = Array.isArray(merged.permissions[key]) ? merged.permissions[key] : [];
  const want = (snippet.permissions && snippet.permissions[key]) || [];
  for (const item of want) {
    if (!have.includes(item)) {
      have.push(item);
      added[key].push(item);
    }
  }
  merged.permissions[key] = have;
}

merged.env = merged.env || {};
for (const [k, v] of Object.entries(snippet.env || {})) {
  if (!(k in merged.env)) {
    merged.env[k] = v;
    added.env.push(`${k}=${v}`);
  } else if (merged.env[k] !== v) {
    console.log(`Kept your existing env ${k}=${merged.env[k]} (snippet suggests ${v}).`);
  }
}

const total = added.allow.length + added.deny.length + added.env.length;
console.log(`Target: ${target}${exists ? "" : " (will be created)"}`);
console.log(`Add to permissions.allow (${added.allow.length}):`);
added.allow.forEach((x) => console.log("  + " + x));
console.log(`Add to permissions.deny (${added.deny.length}):`);
added.deny.forEach((x) => console.log("  + " + x));
console.log(`Add to env (${added.env.length}):`);
added.env.forEach((x) => console.log("  + " + x));

if (dry) {
  console.log("\nDry run: nothing was written.");
  process.exit(0);
}
if (total === 0) {
  console.log("\nAlready up to date. Nothing written.");
  process.exit(0);
}

fs.mkdirSync(root, { recursive: true });
if (exists) {
  const stamp = new Date().toISOString().replace(/[-:T]/g, "").slice(0, 14);
  const bak = `${target}.bak-${stamp}`;
  fs.copyFileSync(target, bak);
  console.log(`\nBackup saved: ${bak}`);
}
fs.writeFileSync(target, JSON.stringify(merged, null, 2) + "\n");
console.log(`Written: ${target}`);
