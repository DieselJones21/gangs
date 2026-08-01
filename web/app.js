const app = document.getElementById('app');
let state = null;

const resourceName = typeof GetParentResourceName === 'function'
  ? GetParentResourceName()
  : 'gangs';

async function nui(event, data = {}) {
  const resp = await fetch(`https://${resourceName}/${event}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  });
  try {
    return await resp.json();
  } catch (_) {
    return null;
  }
}

function setTab(tab) {
  document.querySelectorAll('.nav-btn').forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.tab === tab);
  });
  document.querySelectorAll('.tab').forEach((el) => {
    el.classList.toggle('active', el.id === `tab-${tab}`);
  });
}

function esc(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function renderOverview() {
  const p = state.player || {};
  const org = state.organization;
  document.getElementById('playerMeta').textContent = `${p.name || 'Unknown'} · ${p.currency || 0} ${state.config?.currencyLabel || 'BTC'}`;

  document.getElementById('overviewStats').innerHTML = `
    <div class="stat"><span>Currency</span><strong>${esc(p.currency || 0)}</strong></div>
    <div class="stat"><span>Title</span><strong>${esc(p.title?.Title || 'Pickpocket')}</strong></div>
    <div class="stat"><span>Kills</span><strong>${esc(p.stats?.kills || 0)}</strong></div>
    <div class="stat"><span>Wars Won</span><strong>${esc(p.stats?.wars_won || 0)}</strong></div>
  `;

  document.getElementById('overviewOrg').innerHTML = org
    ? `<h3 style="margin:0 0 8px;font-family:Syne,sans-serif;">${esc(org.label)}</h3>
       <p class="muted">Power rating ${esc(org.power)} · Bank ${esc(org.bank)} · Role ${esc(p.roleName || 'Member')}</p>`
    : `<p class="muted">You are not in an organization. Create one from the Organization tab.</p>`;
}

function renderOrg() {
  const panel = document.getElementById('orgPanel');
  const org = state.organization;
  const cfg = state.config || {};
  const perms = state.player?.permissions || {};

  if (!org) {
    if (!cfg.canCreate) {
      panel.innerHTML = `<div class="empty">Organization creation is disabled on this server.</div>`;
      return;
    }
    panel.innerHTML = `
      <div class="panel form-panel">
        <p class="muted">Cost to create: ${esc(cfg.createPrice)} ${esc(cfg.currencyLabel)}</p>
        <label>Organization Name</label>
        <input id="orgName" type="text" maxlength="32" placeholder="Los Santos Cartel" />
        <label>Color</label>
        <input id="orgColor" type="color" value="#c43c2f" />
        <button class="primary" id="createOrgBtn">Create Organization</button>
      </div>`;
    document.getElementById('createOrgBtn').onclick = async () => {
      const label = document.getElementById('orgName').value.trim();
      const color = document.getElementById('orgColor').value;
      const result = await nui('createOrg', { label, color });
      if (result?.success && result.data) {
        state = result.data;
        renderAll();
      } else {
        alert(result?.error || 'Failed to create organization');
      }
    };
    return;
  }

  const members = (org.members || []).map((m) => `
    <div class="row">
      <div>
        <h3>${esc(m.name)} ${m.online ? '<span class="badge">Online</span>' : ''}</h3>
        <p>${esc(m.roleName)}</p>
      </div>
      <div class="actions">
        ${perms.canPromote ? `<select data-role="${esc(m.identifier)}">
          ${(org.roles || []).map((r) => `<option value="${r.id}" ${r.id === m.roleId ? 'selected' : ''}>${esc(r.name)}</option>`).join('')}
        </select>` : ''}
        ${perms.canKick ? `<button class="danger" data-kick="${esc(m.identifier)}">Kick</button>` : ''}
      </div>
    </div>
  `).join('');

  panel.innerHTML = `
    <div class="panel" style="margin-bottom:12px;">
      <h3 style="margin:0 0 6px;font-family:Syne,sans-serif;color:${esc(org.color)}">${esc(org.label)}</h3>
      <p class="muted">Bank: ${esc(org.bank)} · Members: ${esc(org.members.length)} · Power: ${esc(org.power)}</p>
      <div class="actions" style="margin-top:12px;justify-content:flex-start;">
        ${perms.canInvite ? `<button class="soft" id="inviteBtn">Invite Nearby</button>` : ''}
        ${perms.canManageBank ? `<button class="soft" id="withdrawBtn">Withdraw 100</button>` : ''}
        <button class="danger" id="leaveBtn">Leave</button>
      </div>
    </div>
    <div class="list">${members || '<div class="empty">No members</div>'}</div>
  `;

  const leaveBtn = document.getElementById('leaveBtn');
  if (leaveBtn) {
    leaveBtn.onclick = async () => {
      const result = await nui('leaveOrg');
      if (result?.success && result.data) {
        state = result.data;
        renderAll();
      }
    };
  }

  const inviteBtn = document.getElementById('inviteBtn');
  if (inviteBtn) {
    inviteBtn.onclick = async () => {
      const nearby = await nui('getNearbyPlayers');
      if (!nearby?.length) {
        alert('No players nearby');
        return;
      }
      const targetId = nearby[0].id;
      const result = await nui('invite', { targetId });
      if (!result?.success) alert(result?.error || 'Invite failed');
      else if (result.data) { state = result.data; renderAll(); }
    };
  }

  const withdrawBtn = document.getElementById('withdrawBtn');
  if (withdrawBtn) {
    withdrawBtn.onclick = async () => {
      const result = await nui('withdrawBank', { amount: 100 });
      if (result?.success && result.data) { state = result.data; renderAll(); }
      else alert(result?.error || 'Withdraw failed');
    };
  }

  panel.querySelectorAll('[data-kick]').forEach((btn) => {
    btn.onclick = async () => {
      const result = await nui('kick', { identifier: btn.dataset.kick });
      if (result?.success && result.data) { state = result.data; renderAll(); }
      else alert(result?.error || 'Kick failed');
    };
  });

  panel.querySelectorAll('select[data-role]').forEach((sel) => {
    sel.onchange = async () => {
      const result = await nui('setRole', {
        identifier: sel.dataset.role,
        roleId: Number(sel.value),
      });
      if (result?.success && result.data) { state = result.data; renderAll(); }
      else alert(result?.error || 'Role update failed');
    };
  });
}

function renderZones() {
  const panel = document.getElementById('zonesPanel');
  const orgName = state.organization?.name;
  const perms = state.player?.permissions || {};
  const zones = state.zones || [];

  if (!zones.length) {
    panel.innerHTML = `<div class="empty">No territories configured yet. Admins can use /zoneeditor.</div>`;
    return;
  }

  panel.innerHTML = zones.map((z) => {
    const owned = orgName && z.owner === orgName;
    const canWar = orgName && !owned && z.type !== 'continental' && perms.canStartWar;
    return `
      <div class="row">
        <div>
          <h3>${esc(z.title)} <span class="badge">${esc(z.type)}</span></h3>
          <p>Owner: ${esc(z.owner || 'Unowned')} · Protection ${esc(z.protection)} · NPCs ${esc(z.npcCount)}${z.inWar ? ' · IN WAR' : ''}</p>
        </div>
        <div class="actions">
          ${canWar ? `<button class="danger" data-war="${esc(z.key)}">Start War</button>` : ''}
          ${owned && perms.canManageZones ? `<button class="soft" data-prot="${esc(z.key)}">Upgrade Protection</button>` : ''}
          ${owned && perms.canManageZones ? `<button class="soft" data-npc="${esc(z.key)}">Upgrade NPCs</button>` : ''}
        </div>
      </div>
    `;
  }).join('');

  panel.querySelectorAll('[data-war]').forEach((btn) => {
    btn.onclick = async () => {
      const result = await nui('startWar', { zoneKey: btn.dataset.war });
      if (result?.success && result.data) { state = result.data; renderAll(); }
      else alert(result?.error || 'Could not start war');
    };
  });
  panel.querySelectorAll('[data-prot]').forEach((btn) => {
    btn.onclick = async () => {
      const result = await nui('upgradeProtection', { zoneKey: btn.dataset.prot });
      if (result?.success && result.data) { state = result.data; renderAll(); }
      else alert(result?.error || 'Upgrade failed');
    };
  });
  panel.querySelectorAll('[data-npc]').forEach((btn) => {
    btn.onclick = async () => {
      const result = await nui('upgradeNPCs', { zoneKey: btn.dataset.npc });
      if (result?.success && result.data) { state = result.data; renderAll(); }
      else alert(result?.error || 'Upgrade failed');
    };
  });
}

function renderWars() {
  const panel = document.getElementById('warsPanel');
  const wars = state.wars || [];
  if (!wars.length) {
    panel.innerHTML = `<div class="empty">No active wars.</div>`;
    return;
  }
  panel.innerHTML = wars.map((w) => `
    <div class="row">
      <div>
        <h3>${esc(w.zoneTitle)}</h3>
        <p>${esc(w.attacker)} ${esc(w.attackerScore)} vs ${esc(w.defender || 'Unowned')} ${esc(w.defenderScore)}</p>
      </div>
      <span class="badge">Live</span>
    </div>
  `).join('');
}

function renderBounties() {
  const panel = document.getElementById('bountiesPanel');
  const bounties = state.bounties || [];
  panel.innerHTML = bounties.length
    ? bounties.map((b) => `
      <div class="row">
        <div>
          <h3>${esc(b.targetName)}</h3>
          <p>${esc(b.amount)} ${esc(state.config?.currencyLabel)} · by ${esc(b.placerName)}${b.reason ? ` · ${esc(b.reason)}` : ''}</p>
        </div>
      </div>
    `).join('')
    : `<div class="empty">No active bounties.</div>`;
}

function renderBoard() {
  const panel = document.getElementById('boardPanel');
  const rows = state.leaderboard || [];
  panel.innerHTML = rows.length
    ? rows.map((r, i) => `
      <div class="row">
        <div>
          <h3>#${i + 1} ${esc(r.name)}</h3>
          <p>${esc(r.title)} · Wars ${esc(r.warsWon)} · Kills ${esc(r.kills)} · Bounties ${esc(r.bounties)}</p>
        </div>
      </div>
    `).join('')
    : `<div class="empty">No criminal stats yet.</div>`;
}

function renderAll() {
  if (!state) return;
  renderOverview();
  renderOrg();
  renderZones();
  renderWars();
  renderBounties();
  renderBoard();
}

document.querySelectorAll('.nav-btn').forEach((btn) => {
  btn.addEventListener('click', () => setTab(btn.dataset.tab));
});

document.getElementById('closeBtn').addEventListener('click', () => {
  app.classList.add('hidden');
  nui('close');
});

document.getElementById('placeBountyBtn').addEventListener('click', async () => {
  const targetId = Number(document.getElementById('bountyTarget').value);
  const amount = Number(document.getElementById('bountyAmount').value);
  const reason = document.getElementById('bountyReason').value;
  const result = await nui('placeBounty', { targetId, amount, reason });
  if (result?.success && result.data) {
    state = result.data;
    renderAll();
  } else {
    alert(result?.error || 'Could not place bounty');
  }
});

window.addEventListener('message', (event) => {
  const msg = event.data;
  if (!msg || !msg.action) return;
  if (msg.action === 'open' || msg.action === 'update') {
    state = msg.data;
    app.classList.remove('hidden');
    renderAll();
  }
});

window.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && !app.classList.contains('hidden')) {
    app.classList.add('hidden');
    nui('close');
  }
});
