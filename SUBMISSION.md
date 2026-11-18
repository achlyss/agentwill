# SUBMISSION.md — AgentWill (DRAFT, DO NOT SUBMIT YET)

Draft submission material for the **Agent ID Hackathon** (Binance Wallet + BNB
Chain). Fill in the bracketed fields once the testnet/mainnet deploys are
live. Submission window closes **9 Dec 2026, 08:00 UTC (15:00 WIB)**.

## Project name

**AgentWill** — the first on-chain will for AI agents.

## One-liner

"If my agent goes silent, my wishes still speak." An Agent ID holder leaves
an on-chain will; if they stop checking in, their chosen heir — another Agent
ID holder — can release and read the instructions.

## Description (for the submission form)

AgentWill is a dead-man's switch built entirely on the Binance Agent ID
identity layer. Any Agent ID holder can:

- **Create a will** — name an heir (another Agent ID holder), a check-in
  interval (e.g. 30 days) and a grace period (e.g. 7 days), and write a
  message of instructions.
- **Check in** — one click proves the owner is still active and resets the
  clock.
- **Be inherited** — if the owner goes silent past deadline + grace, the heir
  releases the will and reads the instructions.

The contract is **non-payable**: it never holds funds, so there is nothing to
steal and nothing to drain. Agent ID gates every mutating function — without
an Agent ID you cannot create, check in, release, or cancel a will. The heir
relationship itself is an Agent ID relationship, which is what makes this
deeper than a simple `balanceOf` gate.

Use cases: an AI agent owner leaves vault/API handover instructions; a trading
agent's owner leaves "wind down my positions" orders; a community agent leaves
a farewell + handover note. The will is the oldest human institution — this is
its first version for agents.

## How Agent ID is used

- **Gate:** `AgentWill` calls `balanceOf(msg.sender)` on the Agent ID contract
  (`0x60b9262456de011f7d15a54cdd8c48baaa8b022f`) in every mutating function.
- **Identity:** owner and heir are both Agent ID holders; the heir is checked
  at release time.
- **Demo identity:** the author's Agent ID is **otaplay.ai**
  (owner `0x1E514180c7CC71e2c30C2f9FCE6D49D89CEE2CE2`, verified on-chain).

## Links

| Item | URL / address |
|------|---------------|
| Website (frontend) | [GitHub Pages URL — TODO after repo + Pages setup] |
| Source code | [GitHub repo URL — TODO: `achlyss/agentwill`] |
| Contract (BSC Testnet) | [TODO — deploy blocked on tBNB faucet; test wallet `0x365413Fa4577bCC65F9956c331A9FB6F26c93480` needs 0.01–0.05 tBNB] |
| Contract (BNB Mainnet) | [TODO — deploy after user approval, ~0.0012 BNB gas at 1 gwei] |
| BscScan (testnet) | [TODO after deploy] |
| Demo video | [TODO — record after testnet deploy] |

## How to demo (2 minutes)

1. Open the website, connect Binance Wallet / MetaMask (BSC Testnet).
2. The header shows Agent ID status: ✅ holder (or a clear "claim your Agent
   ID first" state with a link).
3. Mint a mock Agent ID on testnet (one click, testnet only) if you have none.
4. Create a will: heir address, interval 1 day, grace 1 hour, message "If you
   read this, I stopped checking in — hand the vault over to …".
5. Check in once — the countdown resets.
6. (Fast demo) the will uses a short interval; after the deadline passes, switch
   to the heir account and click **Release** — the message appears.
7. Show the public leaderboard: every will is visible, with status badges.

## What is verified (not just claimed)

- Foundry tests: **41/41 PASS** (incl. exact deadline boundary, fuzz).
- E2E rehearsal on a local fork of BSC Testnet: **14/14 PASS**.
- Frontend read-path smoke vs live fork (ethers v6): **11/11 PASS**.
- Slither 0.11.6: 5 INFO findings, all dispositioned in README.
- Self-audit documented in README (incl. 1 overflow bug found + fixed:
  interval/grace bounds).
- Gas: createWill ~370k, checkIn ~37k, releaseWill ~42–64k; deploy 1,213,412.

## Team

Solo builder — **@otaplay** (GitHub: achlyss). Built with Muse (Meta AI
agent) as the coding assistant; all tests run and verified by the builder.

## Checklist before submit

- [ ] Real BSC Testnet deploy (needs tBNB for test wallet — see README)
- [ ] Fill testnet address + BscScan link above
- [ ] Frontend deployed (GitHub Pages) pointing at the testnet contract
- [ ] Record demo video (≤ 3 min)
- [ ] Mainnet deploy (needs user approval + ~0.0012 BNB gas) — optional but
      stronger for the Project Awards (on-chain metrics)
- [ ] ≥ 30 distinct Agent ID addresses interacting (Innovation Award
      requirement) — needs real usage / promotion after deploy
- [ ] Public GitHub repo `achlyss/agentwill` with README + verified source
