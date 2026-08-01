const app = document.getElementById('app');
const toastEl = document.getElementById('toast');
const warHudEl = document.getElementById('warHud');
let state = null;
let toastTimer = null;
let busy = false;
let clockOffset = 0;

const resourceName = typeof GetParentResourceName === 'function'
  ? GetParentResourceName()
  : 'gangs';

function showToast(message, type = 'error') {
  if (!toastEl) return;
  toastEl.textContent = message || 'Something went wrong';
  toastEl.classList.remove('hidden', 'error', 'success');
  toastEl.classList.add(type === 'success' ? 'success' : 'error');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toastEl.classList.add('hidden'), 3500);
}

async function nui(event, data = {}) {
  const controller = typeof AbortController !== 'undefined' ? new AbortController() : null;
  const timer = controller ? setTimeout(() => controller.abort(), 15000) : null;
  try {
    const resp = await fetch(`https://${resourceName}/${event}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data),
      signal: controller ? controller.signal : undefined,
    });
    const text = await resp.text();
    if (!text) return null;
    try {
      return JSON.parse(text);
    } catch (_) {
      return null;
    }
  } catch (err) {
    return { success: false, error: err?.name === 'AbortError' ? 'Request timed out' : 'UI request failed' };
  } finally {
    if (timer) clearTimeout(timer);
  }
}

async function runAction(fn) {
  if (busy) return null;
  busy = true;
  try {
    return await fn();
  } finally {
    busy = false;
  }
}

function applyResult(result, fallbackError) {
  if (result?.success && result.data) {
    state = result.data;
    renderAll();
    return true;
  }
  showToast(result?.error || fallbackError || 'Request failed', 'error');
  return false;
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
        <p id="orgFormError" class="form-error"></p>
        <button class="primary" id="createOrgBtn">Create Organization</button>
      </div>`;

    const btn = document.getElementById('createOrgBtn');
    const errorEl = document.getElementById('orgFormError');
    btn.onclick = async () => {
      const label = document.getElementById('orgName').value.trim();
      const color = document.getElementById('orgColor').value || '#c43c2f';
      if (label.length < 2) {
        errorEl.textContent = 'Enter a name with at least 2 characters.';
        return;
      }

      errorEl.textContent = '';
      btn.disabled = true;
      btn.textContent = 'Creating...';

      const result = await runAction(() => nui('createOrg', { label, color }));

      btn.disabled = false;
      btn.textContent = 'Create Organization';

      if (result?.success && result.data) {
        state = result.data;
        showToast('Organization created', 'success');
        renderAll();
        setTab('org');
        return;
      }

      const message = result?.error || 'Failed to create organization';
      errorEl.textContent = message;
      showToast(message, 'error');
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
          ${(org.roles || []).map((r) => `<option value="${r.id}" ${Number(r.id) === Number(m.roleId) ? 'selected' : ''}>${esc(r.name)}</option>`).join('')}
        </select>` : ''}
        ${perms.canKick ? `<button class="danger" data-kick="${esc(m.identifier)}">Kick</button>` : ''}
      </div>
    </div>
  `).join('');

  panel.innerHTML = `
    <div class="panel" style="margin-bottom:12px;">
      <h3 style="margin:0 0 6px;font-family:Syne,sans-serif;color:${esc(org.color)}">${esc(org.label)}</h3>
      <p class="muted">Bank: ${esc(org.bank)} · Members: ${esc((org.members || []).length)} · Power: ${esc(org.power)}</p>
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
      const result = await runAction(() => nui('leaveOrg'));
      applyResult(result, 'Failed to leave organization');
    };
  }

  const inviteBtn = document.getElementById('inviteBtn');
  if (inviteBtn) {
    inviteBtn.onclick = async () => {
      const nearby = await nui('getNearbyPlayers');
      if (!Array.isArray(nearby) || !nearby.length) {
        showToast('No players nearby', 'error');
        return;
      }
      const result = await runAction(() => nui('invite', { targetId: nearby[0].id }));
      if (applyResult(result, 'Invite failed')) {
        showToast(`Invited ${nearby[0].name || 'player'}`, 'success');
      }
    };
  }

  const withdrawBtn = document.getElementById('withdrawBtn');
  if (withdrawBtn) {
    withdrawBtn.onclick = async () => {
      const result = await runAction(() => nui('withdrawBank', { amount: 100 }));
      applyResult(result, 'Withdraw failed');
    };
  }

  panel.querySelectorAll('[data-kick]').forEach((btn) => {
    btn.onclick = async () => {
      const result = await runAction(() => nui('kick', { identifier: btn.dataset.kick }));
      applyResult(result, 'Kick failed');
    };
  });

  panel.querySelectorAll('select[data-role]').forEach((sel) => {
    sel.onchange = async () => {
      const result = await runAction(() => nui('setRole', {
        identifier: sel.dataset.role,
        roleId: Number(sel.value),
      }));
      applyResult(result, 'Role update failed');
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
      const result = await runAction(() => nui('startWar', { zoneKey: btn.dataset.war }));
      applyResult(result, 'Could not start war');
    };
  });
  panel.querySelectorAll('[data-prot]').forEach((btn) => {
    btn.onclick = async () => {
      const result = await runAction(() => nui('upgradeProtection', { zoneKey: btn.dataset.prot }));
      applyResult(result, 'Upgrade failed');
    };
  });
  panel.querySelectorAll('[data-npc]').forEach((btn) => {
    btn.onclick = async () => {
      const result = await runAction(() => nui('upgradeNPCs', { zoneKey: btn.dataset.npc }));
      applyResult(result, 'Upgrade failed');
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

function initials(label) {
  const parts = String(label || '?').trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return '?';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

function formatScore(n) {
  return Number(n || 0).toLocaleString('en-US');
}

function zoneDisplayId(war) {
  if (war.zoneId != null) return `#${war.zoneId}`;
  let hash = 0;
  const key = String(war.zoneKey || war.zoneTitle || '0');
  for (let i = 0; i < key.length; i += 1) hash = ((hash << 5) - hash) + key.charCodeAt(i);
  return `#${Math.abs(hash % 9000) + 1000}`;
}

function renderWarHud(wars = [], serverTime) {
  if (!warHudEl) return;
  if (typeof serverTime === 'number') {
    clockOffset = serverTime - Math.floor(Date.now() / 1000);
  }

  if (!wars.length) {
    warHudEl.classList.add('hidden');
    warHudEl.innerHTML = '';
    return;
  }

  const now = Math.floor(Date.now() / 1000) + clockOffset;
  warHudEl.classList.remove('hidden');
  warHudEl.innerHTML = wars.map((war) => {
    const duration = Math.max(1, Number(war.duration) || 600);
    const remaining = Math.max(0, Number(war.endsAt || 0) - now);
    const progress = Math.max(0, Math.min(100, ((duration - remaining) / duration) * 100));
    const mins = String(Math.floor(remaining / 60)).padStart(2, '0');
    const secs = String(remaining % 60).padStart(2, '0');
    const atk = Number(war.attackerScore || 0);
    const def = Number(war.defenderScore || 0);
    const total = Math.max(1, atk + def);
    const atkFill = (atk / total) * 100;
    const defFill = (def / total) * 100;
    const leadingColor = atk >= def ? (war.attackerColor || '#e11d2e') : (war.defenderColor || '#2563eb');

    return `
      <article class="war-card">
        <div class="war-top">
          <div class="war-ring" style="--ring-progress:${progress.toFixed(1)}%; --ring-color:${esc(leadingColor)}">
            <span>WAR</span>
          </div>
          <div class="war-meta">
            <h3>ZONE WAR</h3>
            <strong>${esc(zoneDisplayId(war))}</strong>
          </div>
          <div class="war-timer">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 1a11 11 0 1 0 11 11A11.013 11.013 0 0 0 12 1Zm1 11.59V7h-2v6.41l4.29 4.3 1.42-1.42Z"/></svg>
            ${mins}:${secs}
          </div>
        </div>
        <div class="war-team" style="--team-color:${esc(war.attackerColor || '#e11d2e')}">
          <div class="war-logo">${esc(initials(war.attackerLabel))}</div>
          <div class="war-team-copy">
            <strong>${esc(war.attackerLabel || 'Attacker')}</strong>
            <div class="war-bar"><i style="--fill:${atkFill.toFixed(1)}%"></i></div>
          </div>
          <div class="war-score">${esc(formatScore(atk))}</div>
        </div>
        <div class="war-team" style="--team-color:${esc(war.defenderColor || '#2563eb')}">
          <div class="war-logo">${esc(initials(war.defenderLabel))}</div>
          <div class="war-team-copy">
            <strong>${esc(war.defenderLabel || 'Unowned')}</strong>
            <div class="war-bar"><i style="--fill:${defFill.toFixed(1)}%"></i></div>
          </div>
          <div class="war-score">${esc(formatScore(def))}</div>
        </div>
      </article>
    `;
  }).join('');
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
  try {
    renderOverview();
    renderOrg();
    renderZones();
    renderWars();
    renderBounties();
    renderBoard();
  } catch (err) {
    console.error('gangs render error', err);
    showToast('UI render failed', 'error');
  }
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
  const result = await runAction(() => nui('placeBounty', { targetId, amount, reason }));
  if (applyResult(result, 'Could not place bounty')) {
    showToast('Bounty placed', 'success');
  }
});

window.addEventListener('message', (event) => {
  const msg = event.data;
  if (!msg || !msg.action) return;
  if (msg.action === 'open' || msg.action === 'update') {
    state = msg.data;
    app.classList.remove('hidden');
    renderAll();
  } else if (msg.action === 'warHud') {
    renderWarHud(msg.wars || [], msg.serverTime);
  }
});

window.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && !app.classList.contains('hidden')) {
    app.classList.add('hidden');
    nui('close');
  }
});
