// AgentWill frontend — vanilla JS + ethers v6 (CDN). No build step.
// Reads: Agent ID balance, wills (mine / where I am heir / public).
// Writes: createWill, checkIn, releaseWill, cancelWill. Every write is
// confirmed by the user in their own wallet — nothing is ever auto-signed.

(function () {
  "use strict";

  var cfg = window.AGENTWILL_CONFIG;
  var $ = function (id) { return document.getElementById(id); };

  // Minimal ABIs (only what the UI needs).
  var WILL_ABI = [
    "function createWill(address heir, uint256 checkInInterval, uint256 gracePeriod, string message) returns (uint256)",
    "function checkIn(uint256 willId)",
    "function releaseWill(uint256 willId)",
    "function cancelWill(uint256 willId)",
    "function readWill(uint256 willId) view returns (tuple(address owner, address heir, uint256 checkInInterval, uint256 gracePeriod, uint256 lastCheckIn, uint8 status, string message))",
    "function getWillMeta(uint256 willId) view returns (tuple(address owner, address heir, uint256 checkInInterval, uint256 gracePeriod, uint256 lastCheckIn, uint256 releasableAt, uint8 status))",
    "function releasableAt(uint256 willId) view returns (uint256)",
    "function isReleasable(uint256 willId) view returns (bool)",
    "function totalWills() view returns (uint256)",
    "function getAllWillIds() view returns (uint256[])",
    "function getWillIdsByOwner(address account) view returns (uint256[])",
    "function getWillIdsByHeir(address heir) view returns (uint256[])",
    "error NotAgentIDHolder(address account)",
    "error NotWillOwner(address caller)",
    "error NotHeir(address caller)",
    "error CannotReadWill(address caller)",
    "error WillNotActive(uint256 willId)",
    "error NotReleasableYet(uint256 willId, uint256 releasableAt)",
    "error InvalidHeir(address heir)",
    "error InvalidInterval(uint256 interval)",
    "error WillDoesNotExist(uint256 willId)"
  ];
  var AGENT_ID_ABI = [
    "function balanceOf(address account) view returns (uint256)",
    "function mint() returns (uint256)"
  ];

  var state = {
    provider: null, signer: null, account: null, chainId: null,
    will: null, willRead: null, agentId: null, agentIdRead: null,
    net: null, timer: null
  };

  var DAY = 86400;
  var STATUS = ["Active", "Released", "Cancelled"];

  // ---------------------------------------------------------------- utils

  function shortAddr(a) {
    return a ? a.slice(0, 6) + "…" + a.slice(-4) : "—";
  }
  function fmtDate(ts) {
    return new Date(Number(ts) * 1000).toLocaleString(undefined, {
      year: "numeric", month: "short", day: "numeric",
      hour: "2-digit", minute: "2-digit"
    });
  }
  function fmtDuration(sec) {
    sec = Math.max(0, Math.floor(sec));
    var d = Math.floor(sec / DAY);
    var h = Math.floor((sec % DAY) / 3600);
    var m = Math.floor((sec % 3600) / 60);
    if (d > 0) return d + "d " + h + "h";
    if (h > 0) return h + "h " + m + "m";
    return m + "m";
  }
  function fmtInterval(sec) {
    var days = Math.round(sec / DAY);
    return days + (days === 1 ? " day" : " days");
  }
  function toast(msg, isError) {
    var t = $("toast");
    t.textContent = msg;
    t.classList.toggle("error", !!isError);
    t.classList.remove("hidden");
    clearTimeout(t._h);
    t._h = setTimeout(function () { t.classList.add("hidden"); }, 5000);
  }
  function setMsg(el, text, kind) {
    el.textContent = text;
    el.className = "form-msg" + (kind ? " " + kind : "");
  }

  // Map a revert to a friendly sentence. Falls back to the raw message.
  function friendlyError(err) {
    var name = "";
    try {
      name = (err && err.reason) || (err && err.error && err.error.reason) || "";
      if (!name && err && err.data) {
        // ethers v6 decodes custom errors when the ABI contains them;
        // otherwise the raw hex data is all we have.
        name = String(err.data).slice(0, 10);
      }
    } catch (e) { /* ignore */ }
    var map = {
      NotAgentIDHolder: "This wallet does not hold a Binance Agent ID. Claim one free in the Binance app (Wallet > banner > Agent ID), then reconnect.",
      NotWillOwner: "Only the will's owner can do that.",
      NotHeir: "Only the designated heir can release this will.",
      CannotReadWill: "Only the will's owner — or the heir, after release — can read this will.",
      WillNotActive: "This will is no longer active (released or cancelled).",
      NotReleasableYet: "Too early: the deadline + grace period have not passed yet.",
      InvalidHeir: "Pick a valid heir address (not empty, not your own address).",
      InvalidInterval: "The check-in interval must be longer than zero.",
      WillDoesNotExist: "That will does not exist.",
      ACTION_REJECTED: "Transaction rejected in your wallet. Nothing was sent.",
      CALL_EXCEPTION: "The transaction was rejected by the contract. Check the requirements above and try again."
    };
    if (name && map[name]) return map[name];
    var raw = (err && (err.shortMessage || err.message)) || "Transaction failed.";
    return raw.length > 220 ? raw.slice(0, 220) + "…" : raw;
  }

  function txLink(hash) {
    if (!state.net || !hash) return null;
    return state.net.explorer + "/tx/" + hash;
  }

  // ------------------------------------------------------------- connection

  function netConfig(chainId) {
    return cfg.networks[chainId] || null;
  }

  async function connect() {
    if (!window.ethereum) {
      toast("No wallet found. Install MetaMask or open this page in Binance Wallet.", true);
      return;
    }
    try {
      state.provider = new ethers.BrowserProvider(window.ethereum);
      var accounts = await state.provider.send("eth_requestAccounts", []);
      state.account = accounts[0];
      state.signer = await state.provider.getSigner();
      var net = await state.provider.getNetwork();
      state.chainId = Number(net.chainId);
      await afterConnect();
    } catch (err) {
      toast(friendlyError(err), true);
    }
  }

  function bindContracts() {
    state.net = netConfig(state.chainId);
    state.will = state.willRead = state.agentId = state.agentIdRead = null;
    if (!state.net) return;
    if (state.net.will) {
      state.will = new ethers.Contract(state.net.will, WILL_ABI, state.signer);
      state.willRead = new ethers.Contract(state.net.will, WILL_ABI, state.provider);
    }
    if (state.net.agentId) {
      state.agentId = new ethers.Contract(state.net.agentId, AGENT_ID_ABI, state.signer);
      state.agentIdRead = new ethers.Contract(state.net.agentId, AGENT_ID_ABI, state.provider);
    }
  }

  function updateNetworkBadge() {
    var badge = $("networkBadge");
    if (!state.account) { badge.textContent = "Not connected"; badge.className = "network-badge"; return; }
    if (!state.net) {
      badge.textContent = "Unsupported network (chain " + state.chainId + ")";
      badge.className = "network-badge wrong";
      return;
    }
    badge.textContent = state.net.name;
    badge.className = "network-badge live";
  }

  async function switchToDefaultChain() {
    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: "0x" + cfg.defaultChain.toString(16) }]
      });
    } catch (err) {
      if (err && err.code === 4902) {
        var net = netConfig(cfg.defaultChain);
        try {
          await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [{
              chainId: "0x" + cfg.defaultChain.toString(16),
              chainName: net.name,
              nativeCurrency: { name: "BNB", symbol: "BNB", decimals: 18 },
              rpcUrls: [net.rpc],
              blockExplorerUrls: [net.explorer]
            }]
          });
        } catch (e2) { toast(friendlyError(e2), true); }
      } else {
        toast(friendlyError(err), true);
      }
    }
  }

  async function afterConnect() {
    bindContracts();
    updateNetworkBadge();
    $("walletLine").textContent = "Connected: " + state.account + " (chain " + state.chainId + ")";
    $("walletLine").classList.remove("hidden");
    $("connectBtn").textContent = "Connected: " + shortAddr(state.account);
    if (!state.net) {
      setMsg($("createMsg"), "AgentWill is deployed on BSC Testnet (97) and BNB Chain Mainnet (56). Please switch networks.", "error");
      await refreshAgentIdStatus();
      await renderMyWills();
      await renderHeirWills();
      return;
    }
    if (!state.net.will) {
      setMsg($("createMsg"), "AgentWill is not deployed on " + state.net.name + " yet. The testnet deployment is in progress — check back soon.", "error");
    }
    await refreshAgentIdStatus();
    await renderMyWills();
    await renderHeirWills();
    startCountdownTimer();
  }

  // ------------------------------------------------------- Agent ID status

  async function refreshAgentIdStatus() {
    var box = $("agentIdBox"), line = $("agentIdLine"), sub = $("agentIdSub"),
        icon = $("agentIdIcon"), help = $("claimHelp"), text = $("statusText");
    if (!state.account) { text.textContent = "Connect your wallet to check whether it holds a Binance Agent ID."; return; }
    if (!state.agentIdRead) {
      text.textContent = "Agent ID contract is not configured for this network yet.";
      box.classList.add("hidden");
      return;
    }
    text.textContent = "";
    try {
      var bal = await state.agentIdRead.balanceOf(state.account);
      box.classList.remove("hidden");
      if (bal > 0n) {
        box.classList.add("ok"); box.classList.remove("no");
        icon.textContent = "✓";
        line.textContent = "You hold a Binance Agent ID — you can use AgentWill.";
        sub.textContent = "Balance: " + bal.toString() + " Agent ID (non-transferable, one per wallet).";
        help.classList.add("hidden");
      } else {
        box.classList.add("no"); box.classList.remove("ok");
        icon.textContent = "✕";
        line.textContent = "This wallet does not hold a Binance Agent ID yet.";
        sub.textContent = "AgentWill requires an Agent ID to create or release a will.";
        help.classList.remove("hidden");
      }
    } catch (err) {
      text.textContent = "Could not read your Agent ID balance: " + friendlyError(err);
    }
  }

  // ------------------------------------------------------------- will cards

  function willStatus(meta, now) {
    // ethers v6 returns integers as BigInt — normalize before comparing.
    var status = Number(meta.status);
    if (status === 1) return { key: "released", label: "Released" };
    if (status === 2) return { key: "cancelled", label: "Cancelled" };
    var deadline = Number(meta.lastCheckIn) + Number(meta.checkInInterval);
    if (now <= deadline) return { key: "healthy", label: "Healthy", until: deadline, what: "next check-in due in" };
    if (now <= Number(meta.releasableAt)) return { key: "due", label: "Due — grace period", until: Number(meta.releasableAt), what: "releasable in" };
    return { key: "overdue", label: "Overdue — releasable", until: Number(meta.releasableAt), what: "overdue by" };
  }

  function willCard(meta, willId, opts) {
    opts = opts || {};
    var now = Math.floor(Date.now() / 1000);
    var st = willStatus(meta, now);
    var div = document.createElement("div");
    div.className = "will";
    div.dataset.willId = String(willId);

    var head = document.createElement("div");
    head.className = "will-head";
    var title = document.createElement("span");
    title.className = "will-title";
    title.textContent = "Will #" + willId;
    var badge = document.createElement("span");
    badge.className = "badge " + st.key;
    badge.textContent = st.label;
    head.appendChild(title);
    head.appendChild(badge);
    div.appendChild(head);

    var metaEl = document.createElement("p");
    metaEl.className = "will-meta";
    metaEl.innerHTML = "Owner <span class='mono'>" + shortAddr(meta.owner) + "</span> · Heir <span class='mono'>" + shortAddr(meta.heir) + "</span><br>" +
      "Check-in every " + fmtInterval(meta.checkInInterval) + " · Grace " + fmtInterval(meta.gracePeriod) + "<br>" +
      "Last check-in: " + fmtDate(meta.lastCheckIn);
    div.appendChild(metaEl);

    if (st.until !== undefined) {
      var cd = document.createElement("p");
      cd.className = "countdown";
      var diff = st.key === "overdue" ? (now - st.until) : (st.until - now);
      cd.textContent = st.what + " " + fmtDuration(diff) + ".";
      div.appendChild(cd);
    }

    if (opts.message) {
      var msg = document.createElement("p");
      msg.className = "will-msg";
      msg.textContent = "“" + opts.message + "”";
      div.appendChild(msg);
    }

    var actions = document.createElement("div");
    actions.className = "will-actions";
    function addBtn(label, cls, fn, disabled) {
      var b = document.createElement("button");
      b.className = "btn " + (cls || "btn-ghost") + " btn-small";
      b.textContent = label;
      b.disabled = !!disabled;
      b.addEventListener("click", function () { fn(b); });
      actions.appendChild(b);
      return b;
    }
    if (opts.canCheckIn) addBtn("Check in now", "btn-primary", function (b) { doCheckIn(willId, b); });
    if (opts.canRelease) addBtn("Release will", "btn-primary", function (b) { doRelease(willId, b); });
    if (opts.canCancel) addBtn("Cancel will", "btn-danger", function (b) { doCancel(willId, b); });
    if (opts.canRead) addBtn("Read message", "btn-ghost", function (b) { doRead(willId, div, b); });
    if (state.net) {
      var a = document.createElement("a");
      a.className = "btn btn-ghost btn-small";
      a.href = state.net.explorer + "/address/" + state.net.will + "#readContract";
      a.target = "_blank"; a.rel = "noopener";
      a.textContent = "View on BscScan";
      actions.appendChild(a);
    }
    div.appendChild(actions);
    return div;
  }

  function emptyList(text) {
    var p = document.createElement("p");
    p.className = "muted";
    p.textContent = text;
    return p;
  }

  async function renderMyWills() {
    var box = $("myWills");
    box.innerHTML = "";
    if (!state.account) { box.appendChild(emptyList("Connect your wallet to see your wills.")); return; }
    if (!state.willRead) { box.appendChild(emptyList("AgentWill is not deployed on this network yet.")); return; }
    try {
      var ids = await state.willRead.getWillIdsByOwner(state.account);
      if (ids.length === 0) { box.appendChild(emptyList("You have not created a will yet. Use the form above — it takes one transaction.")); return; }
      for (var i = ids.length - 1; i >= 0; i--) {
        var id = ids[i];
        var meta = await state.willRead.getWillMeta(id);
        var card = willCard(meta, Number(id), {
          canCheckIn: Number(meta.status) === 0,
          canCancel: Number(meta.status) === 0,
          canRead: true
        });
        box.appendChild(card);
      }
    } catch (err) {
      box.appendChild(emptyList("Could not load your wills: " + friendlyError(err)));
    }
  }

  async function renderHeirWills() {
    var box = $("heirWills");
    box.innerHTML = "";
    if (!state.account) { box.appendChild(emptyList("Connect your wallet to see wills naming you as heir.")); return; }
    if (!state.willRead) { box.appendChild(emptyList("AgentWill is not deployed on this network yet.")); return; }
    try {
      var ids = await state.willRead.getWillIdsByHeir(state.account);
      if (ids.length === 0) { box.appendChild(emptyList("No will names you as heir (yet).")); return; }
      for (var i = ids.length - 1; i >= 0; i--) {
        var id = ids[i];
        var meta = await state.willRead.getWillMeta(id);
        var releasable = await state.willRead.isReleasable(id);
        var card = willCard(meta, Number(id), {
          canRelease: Number(meta.status) === 0 && releasable,
          canRead: Number(meta.status) === 1
        });
        box.appendChild(card);
      }
    } catch (err) {
      box.appendChild(emptyList("Could not load heir wills: " + friendlyError(err)));
    }
  }

  async function renderLeaderboard() {
    var box = $("leaderboard");
    var count = $("leaderboardCount");
    if (!state.willRead) {
      // Public read-only mode still works if we know the chain: use a
      // read-only provider pointed at the network RPC.
      box.innerHTML = "<p class='muted'>Connect your wallet, or switch to BSC Testnet, to see public wills.</p>";
      count.textContent = "";
      return;
    }
    box.innerHTML = "<p class='muted'>Loading…</p>";
    try {
      var ids = await state.willRead.getAllWillIds();
      count.textContent = ids.length + (ids.length === 1 ? " will" : " wills") + " total";
      if (ids.length === 0) { box.innerHTML = "<p class='muted'>No wills yet — be the first to create one.</p>"; return; }
      var recent = ids.slice(-50).reverse();
      var metas = await Promise.all(recent.map(function (id) { return state.willRead.getWillMeta(id); }));
      var table = document.createElement("table");
      table.innerHTML = "<thead><tr><th>Will</th><th>Owner</th><th>Heir</th><th>Status</th><th>Last check-in</th></tr></thead>";
      var tbody = document.createElement("tbody");
      recent.forEach(function (id, idx) {
        var m = metas[idx];
        var now = Math.floor(Date.now() / 1000);
        var st = willStatus(m, now);
        var tr = document.createElement("tr");
        [["Will", "#" + Number(id)],
         ["Owner", shortAddr(m.owner)],
         ["Heir", shortAddr(m.heir)],
         ["Status", st.label],
         ["Last check-in", fmtDate(m.lastCheckIn)]
        ].forEach(function (pair) {
          var td = document.createElement("td");
          td.setAttribute("data-label", pair[0]);
          td.textContent = pair[1];
          tr.appendChild(td);
        });
        tbody.appendChild(tr);
      });
      table.appendChild(tbody);
      box.innerHTML = "";
      box.appendChild(table);
    } catch (err) {
      box.innerHTML = "<p class='muted'>Could not load public wills: " + friendlyError(err) + "</p>";
    }
  }

  function startCountdownTimer() {
    if (state.timer) return;
    // Re-render countdowns every 30s without refetching everything:
    // simplest correct approach is a light re-render of the two lists.
    state.timer = setInterval(function () {
      if (state.account && state.willRead) { renderMyWills(); renderHeirWills(); }
    }, 30000);
  }

  // ---------------------------------------------------------------- writes

  async function withButton(btn, fn) {
    if (!btn) return fn();
    var old = btn.textContent;
    btn.disabled = true;
    btn.textContent = "Waiting for wallet…";
    try {
      await fn();
    } finally {
      btn.disabled = false;
      btn.textContent = old;
    }
  }

  function needContracts() {
    if (!state.will) {
      toast("AgentWill is not deployed on this network yet.", true);
      return false;
    }
    if (!state.account) {
      toast("Connect your wallet first.", true);
      return false;
    }
    return true;
  }

  async function doCheckIn(willId, btn) {
    if (!needContracts()) return;
    await withButton(btn, async function () {
      try {
        var tx = await state.will.checkIn(willId);
        toast("Check-in sent. Waiting for confirmation…");
        await tx.wait();
        toast("Checked in — your will's clock is reset.");
        await renderMyWills();
      } catch (err) { toast(friendlyError(err), true); }
    });
  }

  async function doRelease(willId, btn) {
    if (!needContracts()) return;
    await withButton(btn, async function () {
      try {
        var tx = await state.will.releaseWill(willId);
        toast("Release sent. Waiting for confirmation…");
        await tx.wait();
        toast("Will released. You can now read the instructions.");
        await renderHeirWills();
        await renderLeaderboard();
      } catch (err) { toast(friendlyError(err), true); }
    });
  }

  async function doCancel(willId, btn) {
    if (!needContracts()) return;
    if (!window.confirm("Cancel will #" + willId + "? This cannot be undone.")) return;
    await withButton(btn, async function () {
      try {
        var tx = await state.will.cancelWill(willId);
        toast("Cancellation sent. Waiting for confirmation…");
        await tx.wait();
        toast("Will cancelled.");
        await renderMyWills();
      } catch (err) { toast(friendlyError(err), true); }
    });
  }

  async function doRead(willId, cardEl, btn) {
    if (!needContracts()) return;
    await withButton(btn, async function () {
      try {
        var w = await state.willRead.readWill(willId);
        var old = cardEl.querySelector(".will-msg");
        if (old) old.remove();
        var msg = document.createElement("p");
        msg.className = "will-msg";
        msg.textContent = "“" + w.message + "”";
        cardEl.insertBefore(msg, cardEl.querySelector(".will-actions"));
      } catch (err) { toast(friendlyError(err), true); }
    });
  }

  async function doCreate(e) {
    e.preventDefault();
    var msgEl = $("createMsg");
    if (!needContracts()) return;
    var heir = $("heirInput").value.trim();
    var message = $("messageInput").value.trim();
    var interval = Number($("intervalSelect").value);
    var grace = Number($("graceSelect").value);

    if (!ethers.isAddress(heir)) { setMsg(msgEl, "Enter a valid heir address (0x…).", "error"); return; }
    if (heir.toLowerCase() === state.account.toLowerCase()) { setMsg(msgEl, "The heir cannot be yourself — name another Agent ID holder.", "error"); return; }
    if (!message) { setMsg(msgEl, "Write a message for your heir first.", "error"); return; }

    var btn = $("createBtn");
    btn.disabled = true;
    btn.textContent = "Waiting for wallet…";
    setMsg(msgEl, "Confirm the transaction in your wallet. Creating a will costs only gas — no fee, no funds are moved.", "");
    try {
      var tx = await state.will.createWill(heir, interval, grace, message);
      setMsg(msgEl, "Transaction sent (" + tx.hash.slice(0, 18) + "…). Waiting for confirmation…", "");
      var receipt = await tx.wait();
      var link = txLink(tx.hash);
      setMsg(msgEl, "Will created! " + (link ? "View it on BscScan." : ""), "ok");
      if (link) {
        var a = document.createElement("a");
        a.href = link; a.target = "_blank"; a.rel = "noopener";
        a.textContent = "View transaction on BscScan";
        msgEl.appendChild(document.createTextNode(" "));
        msgEl.appendChild(a);
      }
      toast("Will created.");
      await renderMyWills();
      await renderLeaderboard();
    } catch (err) {
      setMsg(msgEl, friendlyError(err), "error");
    } finally {
      btn.disabled = false;
      btn.textContent = "Create will";
    }
  }

  // ------------------------------------------------------------------ init

  function init() {
    $("connectBtn").addEventListener("click", function () {
      if (state.account) { afterConnect(); return; }
      connect();
    });
    $("createForm").addEventListener("submit", doCreate);
    $("refreshBtn").addEventListener("click", renderLeaderboard);
    $("messageInput").addEventListener("input", function () {
      $("msgCount").textContent = String($("messageInput").value.length);
    });
    $("fillExampleBtn").addEventListener("click", function () {
      $("heirInput").value = "0x000000000000000000000000000000000000dEaD";
      $("intervalSelect").value = "2592000";
      $("graceSelect").value = "604800";
      $("messageInput").value = "If you are reading this, I stopped checking in. Please tell the community what happened, wind down my open positions safely, and keep my agent's memory archive. Thank you for carrying this on.";
      $("msgCount").textContent = String($("messageInput").value.length);
      toast("Example loaded — replace the heir address with your real heir.");
    });

    if (window.ethereum) {
      window.ethereum.on("accountsChanged", function (accs) {
        if (accs.length === 0) { window.location.reload(); return; }
        state.account = accs[0];
        afterConnect();
      });
      window.ethereum.on("chainChanged", function () { window.location.reload(); });
      // Silent reconnect if the wallet is already authorized.
      state.provider = new ethers.BrowserProvider(window.ethereum);
      state.provider.listAccounts().then(function (accs) {
        if (accs.length > 0) {
          state.provider.getSigner().then(function (s) {
            state.signer = s;
            state.account = accs[0];
            return state.provider.getNetwork();
          }).then(function (net) {
            state.chainId = Number(net.chainId);
            return afterConnect();
          }).catch(function () { /* stay disconnected */ });
        } else {
          renderLeaderboardReadOnly();
        }
      }).catch(function () { renderLeaderboardReadOnly(); });
    } else {
      renderLeaderboardReadOnly();
    }

    // Contract link (filled when deployed).
    var net = netConfig(cfg.defaultChain);
    if (net && net.will) {
      $("contractLink").href = net.explorer + "/address/" + net.will;
    } else {
      $("contractLink").textContent = "Contract on BscScan (after testnet deploy)";
      $("contractLink").removeAttribute("href");
    }
  }

  // Public leaderboard without a wallet: read-only provider on testnet.
  async function renderLeaderboardReadOnly() {
    var net = netConfig(cfg.defaultChain);
    if (!net || !net.will) {
      $("leaderboard").innerHTML = "<p class='muted'>AgentWill is not deployed yet — the testnet deployment is in progress. Connect a wallet to try it as soon as it lands.</p>";
      return;
    }
    try {
      var ro = new ethers.JsonRpcProvider(net.rpc);
      state.willRead = new ethers.Contract(net.will, WILL_ABI, ro);
      state.net = net;
      await renderLeaderboard();
    } catch (err) {
      $("leaderboard").innerHTML = "<p class='muted'>Could not load public wills.</p>";
    }
  }

  document.addEventListener("DOMContentLoaded", init);
})();
