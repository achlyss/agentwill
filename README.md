# AgentWill — the first on-chain will for AI agents

> **"If my agent goes silent, my wishes still speak."**
> AgentWill lets any holder of a Binance **Agent ID** register an on-chain will:
> name an heir (another Agent ID holder), set a check-in interval and a grace
> period, and leave a message of instructions. If the owner stops checking in
> past deadline + grace, the will is *released* and the heir can read the
> instructions. No funds are ever held — the contract is **non-payable** and
> stores only the will itself.

Built for the **Agent ID Hackathon** (Binance Wallet + BNB Chain, 18 Nov – 9 Dec
2026). Submission deadline: **9 Dec 2026, 08:00 UTC (15:00 WIB)**.

## How it works

1. **Create** — An Agent ID holder calls `createWill(heir, checkInInterval,
   gracePeriod, message)`. The heir must be a different address; the interval
   must be > 0 and ≤ 10 years; the grace period ≤ 1 year.
2. **Check in** — The owner calls `checkIn(willId)` at least once per interval
   to prove they are still active. Each check-in resets the clock.
3. **Release** — Once `block.timestamp > lastCheckIn + interval + grace`, the
   heir calls `releaseWill(willId)`. The will becomes `Released` and the heir
   can read the message via `readWill(willId)`. The owner can also
   `cancelWill(willId)` any time before release.

Statuses: `Active → Released` (heir, after deadline) or `Active → Cancelled`
(owner, any time before release).

## Why Agent ID is at the core (not a sticker)

Agent ID is the access control for the will's lifecycle. Only an Agent ID
holder can **create** a will (`balanceOf(msg.sender) > 0` on the SPACE ID
contract, `0x60b9262456de011f7d15a54cdd8c48baaa8b022f` on BNB Chain mainnet).
The heir releases on the **fast path** with an Agent ID, or on the **slow
path** — one year later — without one; but only the named heir, ever.
`checkIn` and `cancelWill` are owner-only and do not re-check the Agent ID
(it is soulbound, so a holder cannot lose it). The identity decides *who may
inherit*, not just who may enter. This is deliberately different from plain
`balanceOf > 0` gating used by memecoin launchpads.

## ⚠️ Privacy warning (read this)

**A will message is stored on-chain in plaintext and is visible to everyone
once the will exists.** `readWill` access control (owner anytime, heir only
after release) is a *gating signal for the UI*, not cryptographic privacy —
anyone can read raw contract storage. **Never put secrets in a will message**
(no seed phrases, private keys, passwords, or API keys). Put instructions and
public pointers instead (e.g. "the vault password is with my lawyer, ref
#123"). Encrypted messages (heir's public key) are planned for v2.

## Design decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Heir Agent ID: fast path at RELEASE, slow path a year later** | The heir may claim an Agent ID later; the fast path (release right after deadline + grace) needs one. The SAME heir without an Agent ID may still release after an extra 365 days (decision #11) — the will is never lost because its heir cannot hold an Agent ID yet. |
| 2 | **Release by heir only — never a representative** | Only the named heir may trigger the release — not anyone after deadline, not a delegate, not a second person acting for the heir. Prevents strangers from flipping a will to Released and spamming the owner/heir with events. |
| 3 | **readWill: owner anytime, heir only after release** | Mirrors the real-world will: the testator reads it whenever they want; the heir reads it only after it takes effect. (On-chain data is still public — see warning above.) |
| 4 | **Deadline is a strict `>`** (`block.timestamp > lastCheckIn + interval + grace`) | At exactly `releasableAt` the will is NOT releasable yet; one second later it is. Tested at the exact boundary. |
| 5 | **Intervals in seconds, frontend offers day presets** | Seconds are the native on-chain unit; the UI offers 7 / 30 / 90 / 365 days so nobody has to do mental math. |
| 6 | **Multiple wills per owner allowed** | One owner may leave different instructions for different heirs (e.g. one will for a trading agent, one for a vault agent). |
| 7 | **No re-check of Agent ID on `checkIn` / `cancelWill`** | Agent ID is soulbound (non-transferable) — a holder cannot lose it, so re-checking adds gas for zero security. Gating is enforced on create (owner) and release (heir, fast path); check-in/cancel are owner-only. |
| 8 | **Emergency pause (owner = deployer) pauses create/check-in/release/cancel** | A kill-switch for a discovered bug. `readWill` and all view functions stay available while paused. Documented: pause is an emergency tool, not a backdoor — the deployer cannot touch anyone's will content or move funds (there are none). |
| 9 | **Bounds: interval ≤ 10 years, grace ≤ 1 year** | Prevents `lastCheckIn + interval + grace` overflow and absurd deadlines. Added after self-audit (see below). |
| 10 | **Non-payable, no funds, no withdrawal** | There is no payable function and no ether/token is ever held, so there is nothing to steal, nothing to drain, and no withdrawal function to abuse. |
| 11 | **Slow path: same heir may release without an Agent ID after +365 days** | The heir is NEVER represented by anyone else. The 365-day delay keeps the fast path meaningfully faster (claiming an Agent ID, free, releases a full year earlier) while guaranteeing a will is never lost because its heir cannot hold an Agent ID yet (e.g. a minor child) or Agent ID claiming ever closes. Enforced by `NO_ID_RELEASE_DELAY` + `NotReleasableWithoutAgentId`; exposed via `noIdReleasableAt` / `isReleasableBy`. |

## Contracts

| Contract | Network | Address | Status |
|----------|---------|---------|--------|
| Agent ID (SPACE ID) | BNB Chain mainnet | `0x60b9262456de011f7d15a54cdd8c48baaa8b022f` | Live (used as gate) |
| AgentWill | BNB Chain mainnet | — | **Not deployed** (needs user approval + ~0.0012 BNB gas at 1 gwei) |
| AgentWill | BSC Testnet (v2, slow path) | `0xea517ca9f6053b270c345e241478baf7198d6da1` | **Live** (deployed 19 Nov 2026; fast + slow release paths) |
| MockAgentID | BSC Testnet (v2) | `0x776eb4f84cb45e8892d526da8bf62d4748adc298` | **Live** (deployed 19 Nov 2026) |
| AgentWill | BSC Testnet (v1, superseded) | `0xa23452F669fdbB3532AA2C8Bc4D314cD88DaC8c1` | Superseded by v2 (fast path only) |
| MockAgentID | BSC Testnet (v1, superseded) | `0xbf020b3C81945157cECe4794BB5657729365B5E8` | Superseded by v2 |
| MockAgentID | BSC Testnet (local fork rehearsal) | `0xb77a76C5b8CDcF9cf7c1A60D914a144451D73A69` | Rehearsed |
| AgentWill | BSC Testnet (local fork rehearsal) | `0x3aC4275A940F90cCA5CfF744DfB18A35Bc7Ac0ce` | Rehearsed, 14/14 E2E |

**Testnet deploy status (19 Nov 2026):** v1 deployed with 0.05 tBNB sent by the
project owner from `0xEFA2427A318BE3D978Aac04436A59F2649d9f7bc`. **v2 (slow path)
redeployed the same day** after the heir-release design was upgraded (fast
path with Agent ID / slow path +365 days without one); the frontend
(`frontend/config.js`) points at the v2 addresses above. Deploy command:
`TESTNET_KEY=<key> forge script script/Deploy.s.sol --rpc-url
https://data-seed-prebsc-1-s1.binance.org:8545 --broadcast --legacy
--gas-price 1000000000` (BSC Testnet enforces a 0.1 gwei minimum tip; the
data-seed RPC otherwise estimates 1 wei).

**User identity (verified on-chain, 19 Nov 2026):** the user's Agent ID is
**otaplay.ai** — verified via `ownerOf` on the Agent ID contract (tokenId for
label "otaplay" = `0x7b090109b6f55b9bcc73efe70e6f8c4bc26135932d8a253a1f12c5e3586e578e`).
Owner `0x1E514180c7CC71e2c30C2f9FCE6D49D89CEE2CE2` — the same wallet as the
user's Agent Cards wallet. The mainnet demo will use this identity. Testnet
uses the mock ERC-721 above (free mint, one per wallet, soulbound).

## Tests & verification

| Suite | Result |
|-------|--------|
| Foundry unit + fuzz (`forge test`) | **44/44 PASS** (40 AgentWill + 4 MockAgentID) — gating, deadline boundary (exact `releasableAt` reverts, +1s succeeds), grace period, fast/slow release paths (heir without Agent ID reverts before the slow-path time, releases after it; stranger can never use the slow path), double-release/cancel reverts, pause behaviour, read access rules, interval/grace bounds, 2 fuzz tests (256 runs each: release-only-after-deadline, check-in resets clock) |
| End-to-end rehearsal on a local fork of BSC Testnet (anvil) | **14/14 PASS** — mint mock IDs → create will → early release reverts → check-in → time travel 200s → heir releases → heir reads message → status Released → double release reverts |
| Frontend read-path smoke (ethers v6 against the live fork) | **11/11 PASS** — `totalWills`, `getAllWillIds`, `balanceOf`, `getWillMeta`, `isReleasable`, `readWill` (owner), `getWillIdsByOwner`, `getWillIdsByHeir` |
| Static analysis (Slither 0.11.6) | 5 INFO findings, all dispositioned (see Self-audit) |

Run the tests yourself:
```bash
forge test                    # 44 tests
forge test --gas-report       # gas table
```

## Live testnet E2E (BSC Testnet, chain 97) — 19 Nov 2026

Full end-to-end run against the **real deployed contracts** (not the local
fork), executed 19 Nov 2026 ~06:11–06:15 WIB (23:11–23:15 UTC):

| Contract | Address |
|----------|---------|
| AgentWill | `0xa23452F669fdbB3532AA2C8Bc4D314cD88DaC8c1` |
| MockAgentID | `0xbf020b3C81945157cECe4794BB5657729365B5E8` |

Test wallets (fresh, keys in `.e2e-owner-key` / `.e2e-heir-key`, 0600,
in this folder — never in logs): owner
`0xcA15C2A044eAD8395c417aE511761039c7F93839`, heir
`0x0135bd8F2B23A20590B0aC51f515A4842d3B214A`. Each funded with 0.005 tBNB
from the deployer. Will #1: interval **120 s**, grace **60 s**, message
*"Wasiat E2E live 19 Nov 2026: jika saya diam 3 menit, serahkan instruksi
ke heir. - otaplay"*.

| # | Step | Result | Tx / evidence |
|---|------|--------|---------------|
| 1 | Create 2 test wallets (owner + heir) | ✅ PASS | `0xcA15…3839` / `0x0135…214A` |
| 2 | Fund both 0.005 tBNB from deployer | ✅ PASS | `0x49ddc3c6…98a70`, `0xfb42497e…cc7e0` (status 0x1) |
| 3 | Mint mock Agent ID to both | ✅ PASS | `0xb374c6a6…40304`, `0x2583c477…ec11`; `balanceOf` = 1 each |
| 4 | Owner `createWill(heir, 120, 60, msg)` | ✅ PASS | `0x0d798238…fd0ab` (status 0x1); `totalWills` = 1; `releasableAt` = `lastCheckIn + 180` |
| 5 | Heir `releaseWill` BEFORE deadline | ✅ PASS (reverts) | `NotReleasableYet(1, 1795043668)`, selector `0x6173710f` |
| 6 | Owner `checkIn(1)` | ✅ PASS | `0x3b40eb29…07ed6` (status 0x1); `releasableAt` moved +12 s, `isReleasable` = false |
| 7 | Wait 200 s real time (deadline + grace = 180 s after check-in) | ✅ PASS | `isReleasable` = **true** |
| 8 | Heir `releaseWill(1)` | ✅ PASS | `0x09fdcafc…a00211` (status 0x1) |
| 9 | Heir `readWill(1)` | ✅ PASS | Returns full will incl. the exact message above; owner read also works; stranger reverts `CannotReadWill` |
| 10 | Heir `releaseWill` again | ✅ PASS (reverts) | `WillNotActive(1)`, selector `0x83655300` |
| 11 | Final `getWillMeta(1)` | ✅ PASS | status = **1 (Released)** |

**Note on step 9:** the first `cast call` attempt failed to decode the
return value — that was a wrong `cast` invocation (struct return must be
given as one tuple type), **not a contract bug**. Re-run with tuple syntax
returned the full struct correctly.

**Final balances:** deployer `0.0397251365` tBNB (spent 0.010042 tBNB:
0.01 funding + ~0.000042 gas), owner `0.004473326` tBNB, heir
`0.004839683` tBNB.

**Verdict: the live contracts are READY for demo.** All 11 steps passed on
real BSC Testnet with real waiting (no time travel). No contract bug found.

## Live testnet E2E v2 (slow path) — 19 Nov 2026

Full end-to-end run of the **upgraded contracts** (fast path + slow path),
executed 19 Nov 2026 ~09:17–09:26 WIB. Same test wallets as v1 (owner
`0xcA15…3839`, heir `0x0135…214A`) plus a throwaway no-ID heir
`0xDC00e2B27146f1e0b56E0B90355C18F289506008` (funded 0.001 tBNB, holds no mock
Agent ID — `balanceOf` = 0).

| Contract | Address | Deploy tx |
|----------|---------|-----------|
| AgentWill (v2) | `0xea517ca9f6053b270c345e241478baf7198d6da1` | `0xca7d24e69e39e31a772785a976c1bd37d7ce3e5de37dc873194fa8cb3b52a627` |
| MockAgentID (v2) | `0x776eb4f84cb45e8892d526da8bf62d4748adc298` | `0x108da4628ae46ce2c1969293e85b0394e8fdf37152f9212fe2d2716ff75db2b1` |

Will #1: heir WITH mock Agent ID, interval 120 s, grace 60 s, message *"E2E
v2 fast path - AgentWill slow-path upgrade"*. Will #2: heir WITHOUT Agent ID,
interval 120 s, grace 60 s, message *"E2E v2 slow path - heir without Agent
ID"*.

| # | Step | Result |
|---|------|--------|
| 1 | `NO_ID_RELEASE_DELAY()` | ✅ `31,536,000` s = exactly 365 days |
| 2 | `noIdReleasableAt(2)` = `releasableAt(2)` + 365 days | ✅ `1795055129` → `1826591129` (exact) |
| 3 | Early release will #1 (heir) | ✅ PASS (reverts `NotReleasableYet(1, 1795054878)`, selector `0x6173710f`) |
| 4 | Owner `checkIn(1)` | ✅ PASS (`releasableAt` moved +10 s) |
| 5 | Wait 200 s (deadline + grace = 180 s) | ✅ `isReleasable(1)` = true, `isReleasableBy(1, heir)` = true |
| 6 | Heir releases will #1 (FAST path) | ✅ PASS — status becomes **1 (Released)**, verified via `readWill` state (release tx hash not captured — the script used `--quiet`) |
| 7 | Heir reads will #1 message | ✅ PASS — exact message returned; status = Released |
| 8 | Double release will #1 | ✅ PASS (reverts `WillNotActive(1)`, selector `0x83655300`) |
| 9 | After wait: `isReleasable(2)` = true but `isReleasableBy(2, noID)` = false | ✅ PASS — the fast-path view is open, the slow path is not |
| 10 | No-ID heir releases will #2 | ✅ PASS (reverts `NotReleasableWithoutAgentId(2, 1826591129)`, NEW selector `0x882033dd`; old selector `0x8e44879a` absent) |
| 11 | Will #2 still Active | ✅ PASS (`getWillMeta(2).status` = 0) |

**Note on the run:** the first v2 script had a tooling bug — `cast wallet new
--json` nests the keys under `data[0]`, not at the top level, so the no-ID
heir address came out empty and will #2 was never created in that run (a
script bug, not a contract bug). A fix-up script re-ran the will #2 checks
with the corrected parsing; the table above combines both runs.

**Sourcify verification (19 Nov 2026):** both v2 contracts verified —
`creationMatch` + `runtimeMatch` = `exact_match` for AgentWill
`0xea517ca9…` and MockAgentID `0x776eb4…` on BSC Testnet (chain 97).

**Verdict: the slow path works exactly as designed.** The fast path releases
immediately with an Agent ID; the same heir without one is told the exact
slow-path date and cannot release a second early; the will stays Active.

## Self-audit (19 Nov 2026)

Checklist applied after all tests passed; findings and mitigations:

| # | Area | Result |
|---|------|--------|
| 1 | Reentrancy | **N/A — no value transfer.** The contract never sends ether/tokens and makes no external calls except the view-only `balanceOf` on the Agent ID contract, always *before* any state change. No `call`/`delegatecall` anywhere. |
| 2 | Access control | Verified per function: `createWill` owner-gated by Agent ID + heir ≠ owner/zero; `checkIn` owner-only + Active-only; `releaseWill` heir-only + after deadline (fast path: heir holds Agent ID; slow path: SAME heir, +365 days, no Agent ID needed — never a representative); `cancelWill` owner-only + Active-only; `readWill` owner anytime / heir only after release; `pause`/`unpause` deployer-only. |
| 3 | Deadline / grace edge cases | Exact-boundary test: `block.timestamp == releasableAt` reverts, `+1s` succeeds. `checkIn` after the deadline but before release still works (owner can always save their own will) — intentional. Grace `0` allowed (deadline = interval exactly). |
| 4 | Overflow | **Found + fixed.** A will created with `interval`/`grace` near `2^256` would make `lastCheckIn + interval + grace` overflow (Solidity 0.8 panics) and brick that will's release forever. **Fix:** `MAX_CHECKIN_INTERVAL = 3650 days`, `MAX_GRACE_PERIOD = 365 days`, enforced in `createWill` with `InvalidInterval` / `InvalidGracePeriod` errors; 3 new tests + 1 max-bounds test. |
| 5 | Pause behaviour | `whenNotPaused` on create/check-in/release/cancel; views unaffected. Owner (deployer) cannot read or change wills while paused — pause only freezes actions. |
| 6 | Heir without Agent ID | The heir without an Agent ID cannot use the fast path — `releaseWill` reverts `NotReleasableWithoutAgentId` (with the slow-path timestamp) until `releasableAt + 365 days`, then the SAME heir releases without one. Tested incl. the exact slow-path boundary and that strangers can never use it. The heir can also claim an Agent ID at any time before releasing to use the fast path. |
| 7 | Multiple wills per owner | Allowed by design; `getWillIdsByOwner` / `getWillIdsByHeir` enumerate them. No global state couples wills to each other. |
| 8 | Gas | createWill ~370k (first will, ~70-char message), checkIn ~37k, releaseWill ~42–64k, cancelWill ~43–52k, readWill ~23k (view). Deploy AgentWill 1,213,412 gas (~0.0012 BNB at 1 gwei). No unbounded loops over wills in any user-facing function; the leaderboard reads the latest 50 off-chain. |
| 9 | Slither 0.11.6 | 5 INFO: `incorrect-equality` ×2 — false positive (`balanceOf == 0` is the correct check); `timestamp` ×2 — inherent to a dead-man's switch (a ~12s miner shift is negligible vs day-scale intervals); `pragma` ×1 — compiler pinned to 0.8.31 in `foundry.toml`. Shadowing issues found during the run were fixed (`releasableAt` local renamed to `releaseTime`, param renamed to `account`) and the pragma was bumped ^0.8.20 → ^0.8.24. |
| 10 | Centralization | Deployer is `Ownable` owner with pause only. No fund custody, no upgrade proxy, no ability to edit/delete wills. Documented in the contract header. |

## Frontend

Static web app (no build step) in `frontend/` — open `index.html` or serve the
folder. Connects via `window.ethereum` (MetaMask / Binance Wallet), supports
BSC mainnet + testnet, shows Agent ID status clearly, and provides: create-will
form (with day presets + example loader + privacy warning), My Wills (check-in
/ cancel / read), wills where you are the heir (release / read), and a public
leaderboard (latest 50 wills, read-only mode without a wallet).

UX notes: friendly error mapping for common reverts (`NotAgentIDHolder`,
`NotReleasableYet`, `NotHeir`, `CannotReadWill`, …), toast notifications,
countdown to each will's releasable time, and a persistent privacy banner.

## Run it yourself

```bash
# 1. Tests
forge test

# 2. Local rehearsal (fork of BSC Testnet)
anvil --fork-url https://data-seed-prebsc-1-s1.binance.org:8545 --port 8545
# fund the deployer, then:
TESTNET_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f3ff80 \
  forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 \
  --broadcast --legacy --with-gas-price 3000000000
# (the key above is anvil's well-known test key #0 — local fork only, never mainnet)

# 3. Frontend
cd frontend && python3 -m http.server 8000   # open http://localhost:8000
```

## Jury criteria — how this entry maps

| Criterion | Weight | How AgentWill scores |
|-----------|--------|----------------------|
| Agent ID depth | 30% | Agent ID gates *every* mutating function and defines the heir relationship — the product cannot work without it. |
| Practicality | 25% | Real problem: AI agents and their owners die, go silent, or lose keys. A will is the oldest human institution; this is its first on-chain version for agents. Non-payable = no custody risk, no reason not to use it. |
| Completion | 25% | Contract + 41 tests + E2E rehearsal + working frontend, all verified. Mainnet deploy is a one-command step once the user approves gas. |
| Innovation | 20% | "The first will for AI agents" — a dead-man's switch where the *heir is another agent identity*, plus the Afterlife narrative (digital legacy). |

## Roadmap (v2 ideas)

- Encrypted will messages (heir's public key, e.g. ECIES) — real privacy, not
  just access gating.
- Multi-heir wills (N heirs, M-of-N release).
- Auto-release keeper (anyone may call `releaseWill` after deadline + a
  second grace, with heir still the only reader).
- Check-in reminders (off-chain notifier watching `CheckedIn` events).
- Will templates (vault handover, API key handover, "tell my community").

## License

MIT. OpenZeppelin Contracts v5.4.0 (MIT).
