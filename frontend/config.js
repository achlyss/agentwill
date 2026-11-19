// AgentWill frontend configuration.
//
// Fill in the TESTNET addresses after the real BSC Testnet deployment
// (see ../README.md). The MAINNET Agent ID address is the real SPACE ID
// contract; the mainnet AgentWill address stays empty until mainnet deploy
// is approved by the project owner.
//
// You can also override any address from the URL, e.g.:
//   index.html?chain=97&will=0x...&agentId=0x...
// (useful for pointing the UI at a fresh deployment without editing files.)

(function () {
  var params = new URLSearchParams(window.location.search);

  var NETWORKS = {
    56: {
      name: "BNB Chain Mainnet",
      rpc: "https://bsc-dataseed.binance.org",
      explorer: "https://bscscan.com",
      agentId: "0x60b9262456de011f7d15a54cdd8c48baaa8b022f", // real SPACE ID Agent ID
      will: "", // TODO: fill after mainnet deploy (needs owner approval)
    },
    97: {
      name: "BSC Testnet",
      rpc: "https://data-seed-prebsc-1-s1.binance.org:8545",
      explorer: "https://testnet.bscscan.com",
      agentId: "0x776eb4f84cb45e8892d526da8bf62d4748adc298", // MockAgentID (testnet v2 deploy 19 Nov 2026 — slow path)
      will: "0xea517ca9f6053b270c345e241478baf7198d6da1", // AgentWill (testnet v2 deploy 19 Nov 2026 — slow path)
    },
  };

  // Local-fork rehearsal addresses (anvil fork of BSC Testnet, 19 Nov 2026)
  // — kept here for reference only, not used by default:
  //   MockAgentID 0xb77a76C5b8CDcF9cf7c1A60D914a144451D73A69
  //   AgentWill   0x3aC4275A940F90cCA5CfF744DfB18A35Bc7Ac0ce

  var chainOverride = parseInt(params.get("chain") || "", 10);
  var defaultChain = chainOverride === 56 || chainOverride === 97 ? chainOverride : 97;

  if (params.get("agentId")) NETWORKS[defaultChain].agentId = params.get("agentId");
  if (params.get("will")) NETWORKS[defaultChain].will = params.get("will");

  window.AGENTWILL_CONFIG = { networks: NETWORKS, defaultChain: defaultChain };
})();
