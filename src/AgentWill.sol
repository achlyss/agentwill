// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title AgentWill — an on-chain dead-man's switch ("will") for AI agents
/// @author AgentWill (Agent ID Hackathon 2026 — Binance Wallet x BNB Chain)
/// @notice Agent ID holders register a will: a designated heir, a check-in
/// interval, a grace period, and a message / instructions for the heir. If
/// the owner stops checking in past `lastCheckIn + interval + grace`, the
/// heir can release the will and read the instructions.
///
/// TWO release paths, same heir — the heir is NEVER represented by anyone
/// else (only the named heir may release, ever):
///  - FAST path: the heir holds an Agent ID at release time -> release as
///    soon as the deadline + grace has passed.
///  - SLOW path: the SAME heir without an Agent ID -> release only after an
///    extra NO_ID_RELEASE_DELAY (365 days). This is the safety net for heirs
///    who cannot hold an Agent ID yet (e.g. a minor child) and for the case
///    Agent ID claiming ever closes: the will is never lost, it just takes
///    longer. Claiming an Agent ID stays the rational choice, because it
///    releases a full year earlier.
///
/// The contract is NON-PAYABLE: it never holds, receives or moves any funds.
/// There is no payable function, no withdrawal, and no fee. The deployer
/// (owner) only has an emergency `pause`/`unpause` — nothing else.
///
/// @dev PRIVACY WARNING (honest design note): everything stored on-chain is
/// PUBLIC by nature — the message string, the heir address, the timestamps.
/// `readWill` restricts reads to the owner (any time) and the heir (only after
/// release), but that is a UX / gating signal, NOT cryptographic privacy:
/// anyone can read the raw storage / events with an RPC call. NEVER put
/// secrets, private keys, seed phrases or passwords in a will message.
/// Encrypted messages are planned for v2 (see README).
interface IAgentID {
    function balanceOf(address account) external view returns (uint256);
}

contract AgentWill is Ownable, Pausable {
    IAgentID public immutable agentId;

    /// @dev Upper bounds so `lastCheckIn + interval + grace` can never
    /// overflow (Solidity 0.8 reverts on overflow) and no will can be created
    /// with an absurd deadline. 10 years / 1 year are far above any sane use.
    uint256 public constant MAX_CHECKIN_INTERVAL = 3650 days;
    uint256 public constant MAX_GRACE_PERIOD = 365 days;

    /// @dev Extra delay before the SAME heir may release WITHOUT holding an
    /// Agent ID (the "slow path"). The heir is never represented by anyone
    /// else — only the named heir may release, with or without an Agent ID.
    /// 365 days keeps the fast path meaningfully faster: claiming an Agent ID
    /// (free) releases a full year earlier, while a will is never lost just
    /// because its heir cannot hold an Agent ID yet (e.g. a minor child) or
    /// Agent ID claiming ever closes.
    uint256 public constant NO_ID_RELEASE_DELAY = 365 days;

    enum Status {
        Active,
        Released,
        Cancelled
    }

    struct Will {
        address owner;
        address heir;
        uint256 checkInInterval; // seconds between required check-ins
        uint256 gracePeriod; // extra seconds after the deadline before release
        uint256 lastCheckIn; // timestamp of creation / latest check-in
        Status status;
        string message; // PUBLIC on-chain — never put secrets here
    }

    /// @dev Public summary without the message (used by the leaderboard UI,
    /// so it does not need to pull every message).
    struct WillMeta {
        address owner;
        address heir;
        uint256 checkInInterval;
        uint256 gracePeriod;
        uint256 lastCheckIn;
        uint256 releasableAt;
        Status status;
    }

    uint256 private _willCounter; // will IDs start at 1
    mapping(uint256 => Will) private _wills;
    uint256[] private _allWillIds;
    mapping(address => uint256[]) private _willsByOwner;
    mapping(address => uint256[]) private _willsByHeir;

    event WillCreated(
        uint256 indexed willId,
        address indexed owner,
        address indexed heir,
        uint256 checkInInterval,
        uint256 gracePeriod,
        string message
    );
    event CheckedIn(uint256 indexed willId, address indexed owner, uint256 timestamp);
    event WillReleased(uint256 indexed willId, address indexed heir, uint256 timestamp);
    event WillCancelled(uint256 indexed willId, address indexed owner, uint256 timestamp);

    error NotAgentIDHolder(address account);
    error NotWillOwner(address caller);
    error NotHeir(address caller);
    error CannotReadWill(address caller);
    error WillNotActive(uint256 willId);
    error NotReleasableYet(uint256 willId, uint256 releasableAt);
    error NotReleasableWithoutAgentId(uint256 willId, uint256 noIdReleasableAt);
    error InvalidHeir(address heir);
    error InvalidInterval(uint256 interval);
    error InvalidGracePeriod(uint256 gracePeriod);
    error WillDoesNotExist(uint256 willId);

    constructor(address agentId_) Ownable(msg.sender) {
        require(agentId_ != address(0), "AgentWill: agentId is zero");
        agentId = IAgentID(agentId_);
    }

    // ------------------------------------------------------------------------
    // Core actions
    // ------------------------------------------------------------------------

    /// @notice Create a will. Caller must hold an Agent ID.
    /// @dev The heir is NOT required to hold an Agent ID at creation time —
    /// they may claim one later. The Agent ID check for the heir happens at
    /// `releaseWill`, which is where it actually matters. One owner may hold
    /// many wills (e.g. one per heir / per purpose).
    function createWill(address heir, uint256 checkInInterval, uint256 gracePeriod, string calldata message)
        external
        whenNotPaused
        returns (uint256 willId)
    {
        if (agentId.balanceOf(msg.sender) == 0) revert NotAgentIDHolder(msg.sender);
        if (heir == address(0) || heir == msg.sender) revert InvalidHeir(heir);
        if (checkInInterval == 0 || checkInInterval > MAX_CHECKIN_INTERVAL) {
            revert InvalidInterval(checkInInterval);
        }
        if (gracePeriod > MAX_GRACE_PERIOD) revert InvalidGracePeriod(gracePeriod);

        willId = ++_willCounter;
        _wills[willId] = Will({
            owner: msg.sender,
            heir: heir,
            checkInInterval: checkInInterval,
            gracePeriod: gracePeriod,
            lastCheckIn: block.timestamp,
            status: Status.Active,
            message: message
        });
        _allWillIds.push(willId);
        _willsByOwner[msg.sender].push(willId);
        _willsByHeir[heir].push(willId);

        emit WillCreated(willId, msg.sender, heir, checkInInterval, gracePeriod, message);
    }

    /// @notice Prove the agent is still alive: resets the check-in clock.
    /// @dev Only the will owner, only while Active. No Agent ID re-check here:
    /// Agent ID is soulbound (non-transferable, no burn), so an owner who held
    /// one at creation still holds it. Re-checking would only waste gas.
    function checkIn(uint256 willId) external whenNotPaused {
        Will storage will = _getWill(willId);
        if (will.owner != msg.sender) revert NotWillOwner(msg.sender);
        if (will.status != Status.Active) revert WillNotActive(willId);

        will.lastCheckIn = block.timestamp;
        emit CheckedIn(willId, msg.sender, block.timestamp);
    }

    /// @notice Release a will after deadline + grace. Only the designated heir
    /// — never a representative. Two paths, same heir:
    ///  - FAST: the heir holds an Agent ID -> release as soon as the deadline
    ///    + grace has passed.
    ///  - SLOW: the SAME heir without an Agent ID -> release only after an
    ///    extra NO_ID_RELEASE_DELAY. The will is never lost because its heir
    ///    cannot hold an Agent ID yet (e.g. a minor child) or Agent ID
    ///    claiming ever closes; it just takes a year longer.
    /// @dev Releasable strictly AFTER `lastCheckIn + interval + grace`
    /// (block.timestamp > releasableAt). At exactly releasableAt it is NOT
    /// releasable yet — the full interval + grace must have elapsed. The same
    /// strict inequality applies to the slow path.
    function releaseWill(uint256 willId) external whenNotPaused {
        Will storage will = _getWill(willId);
        if (will.status != Status.Active) revert WillNotActive(willId);
        if (will.heir != msg.sender) revert NotHeir(msg.sender);

        uint256 releaseTime = will.lastCheckIn + will.checkInInterval + will.gracePeriod;
        if (block.timestamp <= releaseTime) revert NotReleasableYet(willId, releaseTime);

        if (agentId.balanceOf(msg.sender) == 0) {
            uint256 noIdTime = releaseTime + NO_ID_RELEASE_DELAY;
            if (block.timestamp <= noIdTime) {
                revert NotReleasableWithoutAgentId(willId, noIdTime);
            }
        }

        will.status = Status.Released;
        emit WillReleased(willId, msg.sender, block.timestamp);
    }

    /// @notice Cancel a will. Only the owner, only while Active.
    /// A released will can never be cancelled (the instructions are out).
    function cancelWill(uint256 willId) external whenNotPaused {
        Will storage will = _getWill(willId);
        if (will.owner != msg.sender) revert NotWillOwner(msg.sender);
        if (will.status != Status.Active) revert WillNotActive(willId);

        will.status = Status.Cancelled;
        emit WillCancelled(willId, msg.sender, block.timestamp);
    }

    // ------------------------------------------------------------------------
    // Reads
    // ------------------------------------------------------------------------

    /// @notice Read a full will (including the message).
    /// @dev Gated: the owner any time; the heir only AFTER release; anyone
    /// else reverts. See the contract-level privacy warning: this is a gating
    /// signal, not cryptographic privacy — raw on-chain data is public.
    function readWill(uint256 willId) external view returns (Will memory) {
        Will storage will = _getWill(willId);
        bool isOwner = will.owner == msg.sender;
        bool heirAfterRelease = will.heir == msg.sender && will.status == Status.Released;
        if (!isOwner && !heirAfterRelease) revert CannotReadWill(msg.sender);
        return will;
    }

    /// @notice Public metadata of a will (no message) — for leaderboards.
    function getWillMeta(uint256 willId) external view returns (WillMeta memory) {
        Will storage will = _getWill(willId);
        return WillMeta({
            owner: will.owner,
            heir: will.heir,
            checkInInterval: will.checkInInterval,
            gracePeriod: will.gracePeriod,
            lastCheckIn: will.lastCheckIn,
            releasableAt: will.lastCheckIn + will.checkInInterval + will.gracePeriod,
            status: will.status
        });
    }

    /// @notice Timestamp after which `releaseWill` is allowed for an heir
    /// holding an Agent ID (the fast path, strictly after).
    function releasableAt(uint256 willId) external view returns (uint256) {
        Will storage will = _getWill(willId);
        return will.lastCheckIn + will.checkInInterval + will.gracePeriod;
    }

    /// @notice Timestamp after which the SAME heir may release WITHOUT holding
    /// an Agent ID (the slow path, strictly after): releasableAt + 365 days.
    function noIdReleasableAt(uint256 willId) external view returns (uint256) {
        Will storage will = _getWill(willId);
        return will.lastCheckIn + will.checkInInterval + will.gracePeriod + NO_ID_RELEASE_DELAY;
    }

    /// @notice True when the will is Active and the deadline + grace passed —
    /// i.e. releasable right now by an heir holding an Agent ID (fast path).
    function isReleasable(uint256 willId) external view returns (bool) {
        Will storage will = _getWill(willId);
        if (will.status != Status.Active) return false;
        return block.timestamp > will.lastCheckIn + will.checkInInterval + will.gracePeriod;
    }

    /// @notice True when `account` can release this will RIGHT NOW: it must be
    /// the named heir, the will must be Active, the deadline + grace must have
    /// passed, and the heir must either hold an Agent ID (fast path) or be
    /// past the slow-path time (no Agent ID needed).
    function isReleasableBy(uint256 willId, address account) external view returns (bool) {
        Will storage will = _getWill(willId);
        if (will.status != Status.Active) return false;
        if (will.heir != account) return false;
        uint256 releaseTime = will.lastCheckIn + will.checkInInterval + will.gracePeriod;
        if (block.timestamp <= releaseTime) return false;
        if (agentId.balanceOf(account) > 0) return true;
        return block.timestamp > releaseTime + NO_ID_RELEASE_DELAY;
    }

    function totalWills() external view returns (uint256) {
        return _willCounter;
    }

    function getAllWillIds() external view returns (uint256[] memory) {
        return _allWillIds;
    }

    function getWillIdsByOwner(address account) external view returns (uint256[] memory) {
        return _willsByOwner[account];
    }

    function getWillIdsByHeir(address heir) external view returns (uint256[] memory) {
        return _willsByHeir[heir];
    }

    // ------------------------------------------------------------------------
    // Emergency pause (owner = deployer, documented)
    // ------------------------------------------------------------------------

    /// @notice Pause ALL mutating functions (create / check-in / release /
    /// cancel). Views keep working. Intended only for emergencies (e.g. a
    /// bug is found) — it cannot move funds, because the contract holds none.
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ------------------------------------------------------------------------
    // Internal
    // ------------------------------------------------------------------------

    function _getWill(uint256 willId) internal view returns (Will storage) {
        if (willId == 0 || willId > _willCounter) revert WillDoesNotExist(willId);
        return _wills[willId];
    }
}
