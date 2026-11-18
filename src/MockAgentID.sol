// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockAgentID — testnet stand-in for the real SPACE ID Agent ID
/// @notice Mirrors the real Agent ID's key properties so the testnet behaves
/// like mainnet: exactly ONE token per wallet, NON-TRANSFERABLE (soulbound).
/// Anyone may mint once for free (testnet only). NOT for mainnet use — on
/// mainnet AgentWill points at the real Agent ID contract
/// 0x60b9262456de011f7d15a54cdd8c48baaa8b022f.
contract MockAgentID is ERC721, Ownable {
    uint256 private _nextTokenId = 1;
    mapping(address => bool) public hasMinted;

    error AlreadyMinted(address account);
    error Soulbound();

    constructor() ERC721("Mock Agent ID", "MAID") Ownable(msg.sender) {}

    /// @notice Mint your one testnet Agent ID. Free, one per wallet.
    function mint() external returns (uint256 tokenId) {
        if (hasMinted[msg.sender]) revert AlreadyMinted(msg.sender);
        hasMinted[msg.sender] = true;
        tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);
    }

    /// @dev Soulbound: transfers are blocked; only minting (from == 0) and
    /// burning (to == 0, unused here) are allowed.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }
}
