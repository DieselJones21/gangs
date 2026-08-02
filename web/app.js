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
  if (tab === 'map') {
    requestAnimationFrame(() => renderMap());
  }
}

// GTA V world bounds used to project zone polygons onto the city map SVG
const MAP_BOUNDS = {
  west: -4140,
  east: 4860,
  north: 8400,
  south: -5100,
  width: 1000,
  height: 1000,
};

let selectedZoneKey = null;

function worldToMap(x, y) {
  const px = ((Number(x) - MAP_BOUNDS.west) / (MAP_BOUNDS.east - MAP_BOUNDS.west)) * MAP_BOUNDS.width;
  const py = ((MAP_BOUNDS.north - Number(y)) / (MAP_BOUNDS.north - MAP_BOUNDS.south)) * MAP_BOUNDS.height;
  return {
    x: Math.max(-40, Math.min(MAP_BOUNDS.width + 40, px)),
    y: Math.max(-40, Math.min(MAP_BOUNDS.height + 40, py)),
  };
}

function zoneOwnerLabel(z) {
  return z.ownerLabel || z.owner || 'Unowned';
}

function zoneOwnerColor(z) {
  return z.ownerColor || (z.owner ? '#94a3b8' : '#64748b');
}

function zoneCenter(z) {
  if (z.center && z.center.x != null && z.center.y != null) {
    return { x: Number(z.center.x), y: Number(z.center.y), z: Number(z.center.z || 0) };
  }
  const pts = z.points || [];
  if (!pts.length) return null;
  let sx = 0;
  let sy = 0;
  pts.forEach((p) => {
    sx += Number(p.x ?? p[0] ?? 0);
    sy += Number(p.y ?? p[1] ?? 0);
  });
  return { x: sx / pts.length, y: sy / pts.length, z: 0 };
}

async function setZoneWaypoint(zone) {
  const center = zoneCenter(zone);
  if (!center) {
    showToast('No coordinates for this zone', 'error');
    return;
  }
  const result = await nui('setWaypoint', {
    x: center.x,
    y: center.y,
    label: zone.title || zone.key,
  });
  if (result?.success === false) {
    showToast(result.error || 'Could not set waypoint', 'error');
    return;
  }
  showToast(`Waypoint set: ${zone.title || 'zone'}`, 'success');
}

function selectMapZone(key) {
  selectedZoneKey = key;
  renderMapSelection();
  document.querySelectorAll('.map-zone').forEach((el) => {
    el.classList.toggle('is-selected', el.dataset.key === key);
  });
}

function renderMapSelection() {
  const panel = document.getElementById('mapSelection');
  if (!panel) return;
  const zones = state?.zones || [];
  const z = zones.find((item) => item.key === selectedZoneKey);
  if (!z) {
    panel.className = 'map-selection empty-panel';
    panel.innerHTML = `
      <h3>Select a zone</h3>
      <p class="muted">Tap any territory on the map to see ownership and drop a waypoint.</p>
    `;
    return;
  }

  const color = zoneOwnerColor(z);
  const owner = zoneOwnerLabel(z);
  panel.className = 'map-selection';
  panel.innerHTML = `
    <h3>${esc(z.title)} <span class="badge">${esc(z.type)}</span></h3>
    <div class="owner-line">
      <span class="owner-swatch" style="background:${esc(color)}"></span>
      <span>${z.owner ? `Owned by <strong>${esc(owner)}</strong>` : '<strong>Unowned</strong>'}</span>
    </div>
    <p class="muted">Protection ${esc(z.protection)} · NPCs ${esc(z.npcCount)}${z.inWar ? ' · IN WAR' : ''}</p>
    <div class="actions">
      <button class="primary" id="mapWaypointBtn">Set Waypoint</button>
      ${z.inWar ? '<span class="badge">Live war</span>' : ''}
    </div>
  `;
  const btn = document.getElementById('mapWaypointBtn');
  if (btn) btn.onclick = () => setZoneWaypoint(z);
}

function renderMapLegend(zones) {
  const legend = document.getElementById('mapLegend');
  if (!legend) return;

  const counts = new Map();
  zones.forEach((z) => {
    const key = z.owner || '__unowned__';
    const label = zoneOwnerLabel(z);
    const color = zoneOwnerColor(z);
    const entry = counts.get(key) || { label, color, count: 0 };
    entry.count += 1;
    counts.set(key, entry);
  });

  const rows = Array.from(counts.values()).sort((a, b) => b.count - a.count || a.label.localeCompare(b.label));
  legend.innerHTML = rows.length
    ? rows.map((r) => `
      <div class="map-legend-item">
        <span class="owner-swatch" style="background:${esc(r.color)}"></span>
        <span>${esc(r.label)}</span>
        <span>${esc(r.count)}</span>
      </div>
    `).join('')
    : `<p class="muted">No zones loaded.</p>`;
}

function renderMap() {
  const layer = document.getElementById('mapZones');
  const markers = document.getElementById('mapMarkers');
  if (!layer || !markers || !state) return;

  const zones = state.zones || [];
  renderMapLegend(zones);

  if (!zones.length) {
    layer.innerHTML = '';
    markers.innerHTML = '';
    selectedZoneKey = null;
    renderMapSelection();
    return;
  }

  if (selectedZoneKey && !zones.some((z) => z.key === selectedZoneKey)) {
    selectedZoneKey = null;
  }

  layer.innerHTML = zones.map((z) => {
    const pts = (z.points || [])
      .map((p) => worldToMap(p.x ?? p[0], p.y ?? p[1]))
      .filter((p) => Number.isFinite(p.x) && Number.isFinite(p.y));

    const color = zoneOwnerColor(z);
    const selected = z.key === selectedZoneKey ? ' is-selected' : '';
    const war = z.inWar ? ' is-war' : '';

    if (pts.length >= 3) {
      const points = pts.map((p) => `${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(' ');
      return `<polygon class="map-zone${selected}${war}" data-key="${esc(z.key)}" points="${points}" fill="${esc(color)}" fill-opacity="0.38" stroke="${esc(color)}"></polygon>`;
    }

    const center = zoneCenter(z);
    if (!center) return '';
    const mapped = worldToMap(center.x, center.y);
    return `<circle class="map-zone${selected}${war}" data-key="${esc(z.key)}" cx="${mapped.x.toFixed(1)}" cy="${mapped.y.toFixed(1)}" r="14" fill="${esc(color)}" fill-opacity="0.45" stroke="${esc(color)}"></circle>`;
  }).join('');

  markers.innerHTML = zones.map((z) => {
    const center = zoneCenter(z);
    if (!center) return '';
    const mapped = worldToMap(center.x, center.y);
    const label = (z.title || z.key || '').slice(0, 18);
    return `
      <g class="map-marker" data-key="${esc(z.key)}">
        <circle cx="${mapped.x.toFixed(1)}" cy="${mapped.y.toFixed(1)}" r="3.5" fill="#f8fafc" stroke="${esc(zoneOwnerColor(z))}" stroke-width="2"></circle>
        <text x="${mapped.x.toFixed(1)}" y="${(mapped.y - 10).toFixed(1)}" text-anchor="middle" fill="#e2e8f0" font-size="11" font-family="IBM Plex Sans, sans-serif">${esc(label)}</text>
      </g>
    `;
  }).join('');

  layer.querySelectorAll('.map-zone').forEach((el) => {
    el.addEventListener('click', () => selectMapZone(el.dataset.key));
  });

  renderMapSelection();
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
    ? `<h3 style="margin:0 0 8px;font-family:var(--display);">${esc(org.label)}</h3>
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

  const canLogo = perms.canEditLogo || perms.canManageZones;
  panel.innerHTML = `
    <div class="panel" style="margin-bottom:12px;">
      <div class="org-head">
        <div class="org-logo-preview" style="background:${esc(org.color)}">
          ${org.logo ? `<img src="${esc(org.logo)}" alt="logo" />` : `<span>${esc((org.label || '?').slice(0, 2).toUpperCase())}</span>`}
        </div>
        <div>
          <h3 style="margin:0 0 6px;font-family:Orbitron,sans-serif;color:${esc(org.color)}">${esc(org.label)}</h3>
          <p class="muted">Bank: ${esc(org.bank)} · Members: ${esc((org.members || []).length)} · Power: ${esc(org.power)}</p>
        </div>
      </div>
      ${canLogo ? `
      <div class="form-panel" style="margin-top:14px;">
        <label>Organization Logo Image URL</label>
        <input id="orgLogoUrl" type="url" placeholder="https://i.imgur.com/yourlogo.png" value="${esc(org.logo || '')}" />
        <p class="muted">Shown on war walls for zones your crew is leading.</p>
        <div class="actions" style="justify-content:flex-start;">
          <button class="soft" id="saveLogoBtn">Save Logo</button>
          <button class="ghost" id="clearLogoBtn">Clear</button>
        </div>
      </div>` : ''}
      <div class="actions" style="margin-top:12px;justify-content:flex-start;">
        ${perms.canInvite ? `<button class="soft" id="inviteBtn">Invite Nearby</button>` : ''}
        ${perms.canManageBank ? `<button class="soft" id="withdrawBtn">Withdraw 100</button>` : ''}
        <button class="danger" id="leaveBtn">Leave</button>
      </div>
    </div>
    <div class="list">${members || '<div class="empty">No members</div>'}</div>
  `;

  const saveLogoBtn = document.getElementById('saveLogoBtn');
  if (saveLogoBtn) {
    saveLogoBtn.onclick = async () => {
      const logo = document.getElementById('orgLogoUrl').value.trim();
      const result = await runAction(() => nui('setOrgLogo', { logo }));
      if (applyResult(result, 'Failed to update logo')) showToast('Logo saved', 'success');
    };
  }
  const clearLogoBtn = document.getElementById('clearLogoBtn');
  if (clearLogoBtn) {
    clearLogoBtn.onclick = async () => {
      const result = await runAction(() => nui('setOrgLogo', { logo: '' }));
      if (applyResult(result, 'Failed to clear logo')) showToast('Logo cleared', 'success');
    };
  }

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
    const owner = zoneOwnerLabel(z);
    const color = zoneOwnerColor(z);
    return `
      <div class="row">
        <div>
          <h3>${esc(z.title)} <span class="badge">${esc(z.type)}</span></h3>
          <p><span class="zone-owner-dot" style="background:${esc(color)}"></span>Owner: ${esc(owner)} · Protection ${esc(z.protection)} · NPCs ${esc(z.npcCount)}${z.inWar ? ' · IN WAR' : ''}</p>
        </div>
        <div class="actions">
          <button class="soft" data-waypoint="${esc(z.key)}">Waypoint</button>
          ${canWar ? `<button class="danger" data-war="${esc(z.key)}">Fight for Zone</button>` : ''}
          ${z.inWar ? `<span class="badge">Open contest</span>` : ''}
          ${owned && perms.canManageZones ? `<button class="soft" data-prot="${esc(z.key)}">Upgrade Protection</button>` : ''}
          ${owned && perms.canManageZones ? `<button class="soft" data-npc="${esc(z.key)}">Upgrade NPCs</button>` : ''}
        </div>
      </div>
    `;
  }).join('');

  panel.querySelectorAll('[data-waypoint]').forEach((btn) => {
    btn.onclick = () => {
      const zone = zones.find((z) => z.key === btn.dataset.waypoint);
      if (zone) setZoneWaypoint(zone);
    };
  });
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
    panel.innerHTML = `<div class="empty">No active wars. Start one from Territories — rival crews can jump in and contest the same zone.</div>`;
    return;
  }
  panel.innerHTML = wars.map((w) => {
    const teams = Array.isArray(w.teams) && w.teams.length
      ? w.teams
      : [
        { label: w.attackerLabel || w.attacker, score: w.attackerScore, color: w.attackerColor },
        { label: w.defenderLabel || w.defender || 'Unowned', score: w.defenderScore, color: w.defenderColor },
      ];
    const standings = teams.map((t) => `${t.label || 'Crew'} ${formatScore(t.score)}`).join(' · ');
    return `
      <div class="row">
        <div>
          <h3>${esc(w.zoneTitle)}</h3>
          <p>${esc(standings)}</p>
          <p class="muted">Open contest — hold the zone alive to score. Deaths cost points.</p>
        </div>
        <span class="badge">Live · ${esc(formatRemaining(w.remaining))}</span>
      </div>
    `;
  }).join('');
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

let warHudState = {};
let warHudTimerHandle = null;

function teamLogoHtml(label, color, logo) {
  if (logo) {
    return `<div class="war-logo war-logo-img" style="--team-color:${esc(color)}"><img src="${esc(logo)}" alt="" /></div>`;
  }
  return `<div class="war-logo" style="--team-color:${esc(color)}">${esc(initials(label))}</div>`;
}

function formatRemaining(totalSeconds) {
  const remaining = Math.max(0, Math.floor(Number(totalSeconds) || 0));
  const mins = String(Math.floor(remaining / 60)).padStart(2, '0');
  const secs = String(remaining % 60).padStart(2, '0');
  return `${mins}:${secs}`;
}

function warTeams(war) {
  if (Array.isArray(war.teams) && war.teams.length) {
    return war.teams.map((t) => ({
      name: t.name || t.label,
      label: t.label || t.name || 'Crew',
      color: t.color || '#64748b',
      logo: t.logo || '',
      score: Number(t.score || 0),
    }));
  }
  return [
    {
      name: 'atk',
      label: war.primaryLabel || war.attackerLabel || 'Attacker',
      color: war.primaryColor || war.attackerColor || '#e11d2e',
      logo: war.primaryLogo || war.attackerLogo || '',
      score: Number(war.primaryScore != null ? war.primaryScore : war.attackerScore || 0),
    },
    {
      name: 'def',
      label: war.secondaryLabel || war.defenderLabel || 'Unowned',
      color: war.secondaryColor || war.defenderColor || '#2563eb',
      logo: war.secondaryLogo || war.defenderLogo || '',
      score: Number(war.secondaryScore != null ? war.secondaryScore : war.defenderScore || 0),
    },
  ];
}

function warStructureKey(war) {
  const teams = warTeams(war);
  return [
    war.zoneKey,
    war.zoneTitle,
    war.duration || 600,
    ...teams.map((t) => `${t.name}|${t.label}|${t.color}|${t.logo || ''}`),
  ].join('~');
}

function teamRowsHtml(teams) {
  return teams.map((t, idx) => `
    <div class="war-team" data-team="${esc(t.name)}" style="--team-color:${esc(t.color)}">
      ${teamLogoHtml(t.label, t.color, t.logo)}
      <div class="war-team-copy">
        <strong class="war-name">${esc(t.label)}</strong>
        <div class="war-bar"><i data-role="bar"></i></div>
      </div>
      <div class="war-score" data-role="score">0</div>
      ${idx === 0 ? '<span class="war-lead-tag">LEAD</span>' : ''}
    </div>
  `).join('');
}

function ensureWarCard(war) {
  const zoneKey = String(war.zoneKey);
  let card = null;
  warHudEl.querySelectorAll('.war-card').forEach((el) => {
    if (el.dataset.zone === zoneKey) card = el;
  });
  if (card) return card;

  const durationMin = Math.max(1, Math.round((Number(war.duration) || 600) / 60));
  const teams = warTeams(war);
  card = document.createElement('article');
  card.className = 'war-card war-card-simple is-new';
  card.dataset.zone = String(war.zoneKey);
  card.dataset.structure = warStructureKey(war);
  card.innerHTML = `
    <div class="war-simple-head">
      <div>
        <span class="war-kicker">ZONE WAR · ${durationMin} MIN</span>
        <strong class="war-title">${esc(war.zoneTitle || zoneDisplayId(war))}</strong>
      </div>
      <div class="war-timer" data-role="timer">
        <span class="war-timer-dot"></span>
        <span data-role="timer-text">10:00</span>
      </div>
    </div>
    <div class="war-teams" data-role="teams">
      ${teamRowsHtml(teams)}
    </div>
  `;
  warHudEl.appendChild(card);
  requestAnimationFrame(() => card.classList.remove('is-new'));
  return card;
}

function syncLocalDeadline(card, remaining) {
  const secs = Math.max(0, Math.floor(Number(remaining) || 0));
  card.dataset.endsAtMs = String(Date.now() + secs * 1000);
}

function patchWarCard(card, war) {
  const teams = warTeams(war);
  const structure = warStructureKey(war);
  if (card.dataset.structure !== structure) {
    card.dataset.structure = structure;
    const durationMin = Math.max(1, Math.round((Number(war.duration) || 600) / 60));
    const kicker = card.querySelector('.war-kicker');
    if (kicker) kicker.textContent = `ZONE WAR · ${durationMin} MIN`;
    card.querySelector('.war-title').textContent = war.zoneTitle || zoneDisplayId(war);
    const teamsEl = card.querySelector('[data-role="teams"]');
    if (teamsEl) teamsEl.innerHTML = teamRowsHtml(teams);
  }

  syncLocalDeadline(card, war.remaining != null ? war.remaining : (war.duration || 600));

  const topScore = Math.max(1, ...teams.map((t) => Number(t.score || 0)), 1);
  teams.forEach((t, idx) => {
    const row = card.querySelector(`[data-team="${CSS && CSS.escape ? CSS.escape(t.name) : String(t.name).replace(/"/g, '\\"')}"]`)
      || card.querySelectorAll('.war-team')[idx];
    if (!row) return;
    row.classList.toggle('is-leading', idx === 0 && Number(t.score || 0) > 0);
    const scoreEl = row.querySelector('[data-role="score"]');
    const barEl = row.querySelector('[data-role="bar"]');
    const fill = Math.max(Number(t.score || 0) > 0 ? 4 : 0, (Number(t.score || 0) / topScore) * 100);
    if (scoreEl) scoreEl.textContent = formatScore(t.score);
    if (barEl) barEl.style.width = `${fill.toFixed(1)}%`;
    let tag = row.querySelector('.war-lead-tag');
    if (idx === 0 && Number(t.score || 0) > 0) {
      if (!tag) {
        tag = document.createElement('span');
        tag.className = 'war-lead-tag';
        tag.textContent = 'LEAD';
        row.appendChild(tag);
      }
    } else if (tag) {
      tag.remove();
    }
  });

  const timer = card.querySelector('[data-role="timer-text"]');
  if (timer) {
    const left = Math.max(0, Math.ceil((Number(card.dataset.endsAtMs) - Date.now()) / 1000));
    timer.textContent = formatRemaining(left);
  }
}

function tickWarTimers() {
  if (!warHudEl) return;
  warHudEl.querySelectorAll('.war-card').forEach((card) => {
    const timer = card.querySelector('[data-role="timer-text"]');
    if (!timer || !card.dataset.endsAtMs) return;
    const left = Math.max(0, Math.ceil((Number(card.dataset.endsAtMs) - Date.now()) / 1000));
    timer.textContent = formatRemaining(left);
    card.classList.toggle('is-ending', left <= 30);
  });
}

function startWarTimerLoop() {
  if (warHudTimerHandle) return;
  warHudTimerHandle = setInterval(tickWarTimers, 200);
}

function stopWarTimerLoop() {
  if (!warHudTimerHandle) return;
  clearInterval(warHudTimerHandle);
  warHudTimerHandle = null;
}

function renderWarHud(wars = []) {
  try {
    if (!warHudEl) return;

    if (!Array.isArray(wars) || !wars.length) {
      warHudState = {};
      warHudEl.classList.add('hidden');
      warHudEl.innerHTML = '';
      stopWarTimerLoop();
      return;
    }

    warHudEl.classList.remove('hidden');
    startWarTimerLoop();

    const active = new Set();
    wars.forEach((war) => {
      if (!war || war.zoneKey == null) return;
      const key = String(war.zoneKey);
      active.add(key);
      warHudState[key] = war;
      const card = ensureWarCard(war);
      patchWarCard(card, war);
    });

    warHudEl.querySelectorAll('.war-card').forEach((card) => {
      if (!active.has(card.dataset.zone)) card.remove();
    });
  } catch (err) {
    console.log('gangs warHud error', err);
  }
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
  const orgPanel = document.getElementById('orgBoardPanel');
  const rows = state.leaderboard || [];
  const orgRows = state.orgLeaderboard || [];

  if (panel) {
    panel.innerHTML = rows.length
      ? rows.map((r, i) => `
        <div class="row board-row">
          <span class="board-rank">#${i + 1}</span>
          <div>
            <h3>${esc(r.name)}</h3>
            <p>${esc(r.title)} · Wars ${esc(r.warsWon)} · Kills ${esc(r.kills)} · Bounties ${esc(r.bounties)}</p>
          </div>
        </div>
      `).join('')
      : `<div class="empty">No criminal stats yet.</div>`;
  }

  if (orgPanel) {
    orgPanel.innerHTML = orgRows.length
      ? orgRows.map((r, i) => `
        <div class="row board-row">
          <span class="board-rank">#${i + 1}</span>
          <div>
            <h3><span class="zone-owner-dot" style="background:${esc(r.color || '#64748b')}"></span>${esc(r.label || r.name)}</h3>
            <p>Power ${esc(r.power)} · Zones ${esc(r.zones)} · Members ${esc(r.members)} · Bank ${esc(r.bank)}</p>
          </div>
        </div>
      `).join('')
      : `<div class="empty">No organizations yet.</div>`;
  }
}

function syncServerClock() {
  const serverTime = Number(state?.admin?.serverTime || 0);
  if (serverTime > 0) {
    clockOffset = serverTime * 1000 - Date.now();
  }
}

function nowUnix() {
  return Math.floor((Date.now() + clockOffset) / 1000);
}

function formatCooldownUntil(until) {
  const end = Number(until || 0);
  if (!end) return 'None';
  const remaining = end - nowUnix();
  if (remaining <= 0) return 'None';
  return formatRemaining(remaining);
}

function orgOptionsHtml(selected) {
  const orgs = state.admin?.orgs || [];
  const opts = [`<option value="">Unowned</option>`]
    .concat(orgs.map((o) => {
      const sel = selected && selected === o.name ? ' selected' : '';
      return `<option value="${esc(o.name)}"${sel}>${esc(o.label)}</option>`;
    }));
  return opts.join('');
}

function renderAdmin() {
  const panel = document.getElementById('adminPanel');
  const navAdmin = document.querySelector('.nav-btn[data-tab="admin"]');
  const isAdmin = Boolean(state?.player?.isAdmin && state?.admin);
  if (navAdmin) navAdmin.classList.toggle('hidden', !isAdmin);
  if (!panel) return;

  if (!isAdmin) {
    panel.innerHTML = `<div class="empty">Admin access required.</div>`;
    return;
  }

  syncServerClock();
  const orgs = state.admin.orgs || [];
  const zones = state.zones || [];
  const wars = state.wars || [];
  const defaultZoneCd = state.admin.defaultZoneCooldown || 10;
  const defaultOrgCd = state.admin.defaultOrgCooldown || 5;

  panel.innerHTML = `
    <div class="admin-toolbar">
      <button class="soft" id="adminOpenEditor">Open Zone Editor</button>
      <button class="danger" id="adminClearCooldowns">Clear All Cooldowns</button>
    </div>

    <div class="admin-grid">
      <section class="panel admin-block">
        <h3>Setup Organization</h3>
        <p class="muted">Create an org for an online player (they become the leader).</p>
        <div class="form-panel">
          <label>Organization Name</label>
          <input id="adminOrgName" type="text" maxlength="32" placeholder="Los Santos Cartel" />
          <label>Color</label>
          <input id="adminOrgColor" type="color" value="#c43c2f" />
          <label>Owner Server ID</label>
          <input id="adminOrgOwner" type="number" min="1" placeholder="12" />
          <p id="adminOrgError" class="form-error"></p>
          <button class="primary" id="adminCreateOrgBtn">Create Organization</button>
        </div>
      </section>

      <section class="panel admin-block">
        <h3>Active Wars</h3>
        <p class="muted">Stop a zone war immediately without changing ownership.</p>
        <div class="list admin-list">
          ${wars.length ? wars.map((w) => `
            <div class="row">
              <div>
                <h3>${esc(w.zoneTitle)}</h3>
                <p>${esc(w.attackerLabel)} vs ${esc(w.defenderLabel || 'Unowned')} · ${esc(formatRemaining(w.remaining))}</p>
              </div>
              <div class="actions">
                <button class="danger" data-stop-war="${esc(w.zoneKey)}">Stop War</button>
              </div>
            </div>
          `).join('') : `<div class="empty">No active wars.</div>`}
        </div>
      </section>
    </div>

    <section class="panel admin-block">
      <h3>Organizations</h3>
      <p class="muted">Delete crews or manage their war cooldowns.</p>
      <div class="list admin-list">
        ${orgs.length ? orgs.map((o) => `
          <div class="row admin-row">
            <div>
              <h3><span class="zone-owner-dot" style="background:${esc(o.color)}"></span>${esc(o.label)}</h3>
              <p>${esc(o.memberCount)} members · Power ${esc(o.power)} · CD ${esc(formatCooldownUntil(o.cooldownUntil))}</p>
            </div>
            <div class="actions">
              <button class="soft" data-clear-org-cd="${esc(o.name)}">Clear CD</button>
              <button class="soft" data-set-org-cd="${esc(o.name)}">Set ${esc(defaultOrgCd)}m CD</button>
              <button class="danger" data-delete-org="${esc(o.name)}">Delete</button>
            </div>
          </div>
        `).join('') : `<div class="empty">No organizations yet.</div>`}
      </div>
    </section>

    <section class="panel admin-block">
      <h3>Zones</h3>
      <p class="muted">Assign ownership, stop wars, clear cooldowns, or delete zones.</p>
      <div class="list admin-list">
        ${zones.length ? zones.map((z) => `
          <div class="row admin-row">
            <div class="admin-zone-meta">
              <h3>${esc(z.title)} <span class="badge">${esc(z.type)}</span>${z.inWar ? ' <span class="badge">WAR</span>' : ''}</h3>
              <p>Owner: ${esc(zoneOwnerLabel(z))} · CD ${esc(formatCooldownUntil(z.cooldownUntil))}</p>
              <label class="admin-inline-label">Set owner</label>
              <select data-owner-select="${esc(z.key)}">${orgOptionsHtml(z.owner || '')}</select>
            </div>
            <div class="actions">
              <button class="soft" data-apply-owner="${esc(z.key)}">Apply Owner</button>
              <button class="soft" data-clear-zone-cd="${esc(z.key)}">Clear CD</button>
              <button class="soft" data-set-zone-cd="${esc(z.key)}">Set ${esc(defaultZoneCd)}m CD</button>
              ${z.inWar ? `<button class="danger" data-stop-war="${esc(z.key)}">Stop War</button>` : ''}
              <button class="danger" data-delete-zone="${esc(z.key)}">Delete Zone</button>
            </div>
          </div>
        `).join('') : `<div class="empty">No zones configured. Use Zone Editor.</div>`}
      </div>
    </section>
  `;

  const createBtn = document.getElementById('adminCreateOrgBtn');
  if (createBtn) {
    createBtn.onclick = async () => {
      const errEl = document.getElementById('adminOrgError');
      const label = document.getElementById('adminOrgName')?.value?.trim();
      const color = document.getElementById('adminOrgColor')?.value;
      const ownerSource = Number(document.getElementById('adminOrgOwner')?.value);
      if (!label || label.length < 2) {
        if (errEl) errEl.textContent = 'Enter a valid organization name.';
        return;
      }
      if (!ownerSource) {
        if (errEl) errEl.textContent = 'Enter the owner player server ID.';
        return;
      }
      if (errEl) errEl.textContent = '';
      const result = await runAction(() => nui('adminCreateOrg', { label, color, ownerSource }));
      if (applyResult(result, 'Failed to create organization')) {
        showToast('Organization created', 'success');
      } else if (errEl && result?.error) {
        errEl.textContent = result.error;
      }
    };
  }

  const editorBtn = document.getElementById('adminOpenEditor');
  if (editorBtn) {
    editorBtn.onclick = async () => {
      app.classList.add('hidden');
      document.body.style.background = 'transparent';
      await nui('openZoneEditor');
    };
  }

  const clearAllBtn = document.getElementById('adminClearCooldowns');
  if (clearAllBtn) {
    clearAllBtn.onclick = async () => {
      const result = await runAction(() => nui('adminClearAllCooldowns'));
      if (applyResult(result, 'Failed to clear cooldowns')) {
        showToast('All cooldowns cleared', 'success');
      }
    };
  }

  panel.querySelectorAll('[data-delete-org]').forEach((btn) => {
    btn.onclick = async () => {
      const orgName = btn.dataset.deleteOrg;
      const result = await runAction(() => nui('adminDeleteOrg', { orgName }));
      if (applyResult(result, 'Delete failed')) showToast('Organization deleted', 'success');
    };
  });

  panel.querySelectorAll('[data-clear-org-cd]').forEach((btn) => {
    btn.onclick = async () => {
      const result = await runAction(() => nui('adminSetOrgCooldown', { orgName: btn.dataset.clearOrgCd, minutes: 0 }));
      if (applyResult(result, 'Cooldown update failed')) showToast('Org cooldown cleared', 'success');
    };
  });

  panel.querySelectorAll('[data-set-org-cd]').forEach((btn) => {
    btn.onclick = async () => {
      const result = await runAction(() => nui('adminSetOrgCooldown', { orgName: btn.dataset.setOrgCd, minutes: defaultOrgCd }));
      if (applyResult(result, 'Cooldown update failed')) showToast('Org cooldown set', 'success');
    };
  });

  panel.querySelectorAll('[data-apply-owner]').forEach((btn) => {
    btn.onclick = async () => {
      const zoneKey = btn.dataset.applyOwner;
      const select = panel.querySelector(`select[data-owner-select="${String(zoneKey).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"]`);
      const orgName = select ? select.value : '';
      const result = await runAction(() => nui('adminSetZoneOwner', { zoneKey, orgName }));
      if (applyResult(result, 'Failed to set owner')) showToast('Zone owner updated', 'success');
    };
  });

  panel.querySelectorAll('[data-clear-zone-cd]').forEach((btn) => {
    btn.onclick = async () => {
      const result = await runAction(() => nui('adminSetZoneCooldown', { zoneKey: btn.dataset.clearZoneCd, minutes: 0 }));
      if (applyResult(result, 'Cooldown update failed')) showToast('Zone cooldown cleared', 'success');
    };
  });

  panel.querySelectorAll('[data-set-zone-cd]').forEach((btn) => {
    btn.onclick = async () => {
      const result = await runAction(() => nui('adminSetZoneCooldown', { zoneKey: btn.dataset.setZoneCd, minutes: defaultZoneCd }));
      if (applyResult(result, 'Cooldown update failed')) showToast('Zone cooldown set', 'success');
    };
  });

  panel.querySelectorAll('[data-stop-war]').forEach((btn) => {
    btn.onclick = async () => {
      const result = await runAction(() => nui('adminStopWar', { zoneKey: btn.dataset.stopWar }));
      if (applyResult(result, 'Failed to stop war')) showToast('War stopped', 'success');
    };
  });

  panel.querySelectorAll('[data-delete-zone]').forEach((btn) => {
    btn.onclick = async () => {
      const result = await runAction(() => nui('adminDeleteZone', { zoneKey: btn.dataset.deleteZone }));
      if (applyResult(result, 'Failed to delete zone')) showToast('Zone deleted', 'success');
    };
  });
}

function renderAll() {
  if (!state) return;
  try {
    renderOverview();
    renderOrg();
    renderMap();
    renderZones();
    renderWars();
    renderBounties();
    renderBoard();
    renderAdmin();
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
  document.body.style.background = 'transparent';
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
    renderWarHud(msg.wars || []);
  } else if (msg.action === 'forceTransparent') {
    app.classList.add('hidden');
    document.body.style.background = 'transparent';
    document.documentElement.style.background = 'transparent';
  }
});

window.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && !app.classList.contains('hidden')) {
    app.classList.add('hidden');
    document.body.style.background = 'transparent';
    nui('close');
  }
});
