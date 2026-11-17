(() => {
  'use strict';

  const state = { reports: [], activeIndex: -1, filter: 'all' };
  const $ = (selector) => document.querySelector(selector);
  const esc = (value) => String(value ?? '—').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const valueText = (value) => value === null || value === undefined || value === '' ? 'Not configured' : Array.isArray(value) ? (value.length ? value.join(', ') : 'None') : String(value);
  const numberText = (value) => Number.isFinite(Number(value)) ? String(value) : '—';
  const formatDate = (value) => {
    if (!value) return 'Timestamp unavailable';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return String(value);
    return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'medium' }).format(date);
  };
  const sortByName = (a, b) => String(a.Name || '').localeCompare(String(b.Name || ''));

  function toast(message) {
    const node = $('#toast');
    node.textContent = message;
    node.classList.add('show');
    window.setTimeout(() => node.classList.remove('show'), 3400);
  }

  function setError(message) {
    const node = $('#reportError');
    node.textContent = message || '';
    node.hidden = !message;
  }

  function setLinks() {
    const config = window.WNR_CONFIG || {};
    let owner = config.owner || '';
    let repo = config.repo || '';
    if ((!owner || !repo) && location.hostname.endsWith('.github.io')) {
      owner = owner || location.hostname.split('.')[0];
      const pathParts = location.pathname.split('/').filter(Boolean);
      repo = repo || pathParts[0] || '';
    }
    const repoUrl = owner && repo ? `https://github.com/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}` : '';
    const releaseUrl = config.releaseUrl || (repoUrl ? `${repoUrl}/releases/latest` : '');
    const repoLink = $('#repoLink');
    const releaseLink = $('#releaseLink');
    if (repoUrl) {
      repoLink.href = repoUrl;
      releaseLink.href = releaseUrl;
      $('#githubBadges')?.replaceChildren(...[
        ['stars', `${repoUrl}/stargazers`],
        ['license', `${repoUrl}/blob/main/LICENSE`],
        ['release', releaseUrl]
      ].map(([kind, href]) => {
        const a = document.createElement('a');
        a.href = href; a.target = '_blank'; a.rel = 'noreferrer';
        const img = document.createElement('img');
        img.alt = `GitHub ${kind}`;
        img.loading = 'lazy';
        img.src = kind === 'stars'
          ? `https://img.shields.io/github/stars/${owner}/${repo}?style=flat&color=62e7bf&label=stars`
          : kind === 'license'
            ? `https://img.shields.io/github/license/${owner}/${repo}?style=flat&color=66aaff`
            : `https://img.shields.io/github/v/release/${owner}/${repo}?style=flat&color=b394ff&label=release`;
        a.appendChild(img);
        return a;
      }));
    } else {
      repoLink.href = '#';
      releaseLink.href = '#';
      releaseLink.setAttribute('aria-disabled', 'true');
      releaseLink.title = 'Set owner and repo in docs/assets/config.js to activate release links.';
    }
  }

  function renderBrowserFacts() {
    const facts = [
      ['BROWSER PLATFORM', navigator.userAgentData?.platform || navigator.platform || 'Not exposed'],
      ['LANGUAGE', navigator.language || 'Not exposed'],
      ['LOGICAL CORES', navigator.hardwareConcurrency || 'Not exposed'],
      ['DEVICE MEMORY', navigator.deviceMemory ? `~${navigator.deviceMemory} GB (browser estimate)` : 'Not exposed'],
      ['ONLINE FLAG', navigator.onLine ? 'Browser reports online' : 'Browser reports offline'],
      ['USER AGENT', navigator.userAgent || 'Not exposed']
    ];
    $('#browserFacts').innerHTML = facts.map(([label, value]) => `<div class="browser-fact"><span>${esc(label)}</span><strong>${esc(value)}</strong></div>`).join('');
  }

  function normalizeReport(raw, fileName) {
    if (!raw || typeof raw !== 'object') throw new Error('The JSON root must be an object.');
    const type = raw.ReportType || raw.reportType || 'UnknownReport';
    let before = raw.Before || raw.before || null;
    let after = raw.After || raw.after || null;
    let snapshot = raw.Snapshot || raw.snapshot || null;
    if (type === 'DiagnosticReport' && snapshot) {
      before = snapshot;
      after = snapshot;
    }
    if (!after && snapshot) after = snapshot;
    if (!before && after) before = after;
    if (!before && !after) throw new Error('No Before, After, or Snapshot data was found in this JSON file.');
    const samples = Array.isArray(raw.MonitorSamples) ? raw.MonitorSamples : Array.isArray(raw.monitorSamples) ? raw.monitorSamples : [];
    const actions = Array.isArray(raw.Actions) ? raw.Actions : Array.isArray(raw.actions) ? raw.actions : [];
    const changes = Array.isArray(raw.Changes) ? raw.Changes : Array.isArray(raw.changes) ? raw.changes : buildDiff(before, after);
    return {
      raw, fileName, type,
      generatedAt: raw.GeneratedAt || raw.generatedAt || raw.Generated || null,
      computerName: raw.ComputerName || raw.computerName || after?.Environment?.ComputerName || after?.ComputerName || 'Unknown host',
      before, after, samples, actions, changes,
      summary: raw.Summary || raw.summary || {},
      backupPath: raw.BackupPath || raw.backupPath || ''
    };
  }

  function flattenSnapshot(snapshot) {
    const map = new Map();
    if (!snapshot) return map;
    const env = snapshot.Environment || {};
    [['System.Windows', env.WindowsCaption], ['System.Build', env.Build], ['System.Architecture', env.OSArchitecture], ['System.RAM_GB', env.RAMGB], ['System.CPU', env.CPU]].forEach(([k, v]) => map.set(k, valueText(v)));
    const s = snapshot.MainSettings || {};
    ['AllowInsecureGuestAuth_Runtime','AllowInsecureGuestAuth_Policy','GuestLogonsCmdlet','RequireSecuritySignature','EnableSecuritySignature','PolicyRequireSecuritySignature','RequireSigningCmdlet'].forEach((key) => map.set(`SMB.${key}`, valueText(s[key])));
    (s.Binding || []).forEach((item) => map.set(`Binding.${item.Name}`, String(Boolean(item.Enabled))));
    (snapshot.Adapters || []).forEach((adapter) => {
      const prefix = `Adapter.${adapter.Name}.`;
      map.set(prefix + 'Status', valueText(adapter.Status));
      map.set(prefix + 'IPv4', valueText(adapter.IPv4Address));
      map.set(prefix + 'Gateway', valueText(adapter.Gateway));
    });
    (snapshot.Services || []).forEach((service) => map.set(`Service.${service.Name}`, `${valueText(service.Status)} / ${valueText(service.StartType)}`));
    (snapshot.Firewall || []).forEach((item) => map.set(`Firewall.${item.Group}`, item.EnabledRules === null || item.EnabledRules === undefined ? 'Unavailable' : `${item.EnabledRules} enabled rule(s)`));
    const c = snapshot.Connectivity || {};
    map.set('Network.DefaultGateways', valueText(c.DefaultGateways));
    map.set('Network.DnsServers', valueText(c.DnsServers));
    map.set('Network.GatewayReachable', valueText(c.GatewayReachable));
    map.set('Network.PublicDnsResolution', valueText(c.PublicDnsResolution));
    return map;
  }

  function buildDiff(before, after) {
    const left = flattenSnapshot(before);
    const right = flattenSnapshot(after);
    const keys = [...new Set([...left.keys(), ...right.keys()])].sort();
    return keys.map((key) => {
      const hasLeft = left.has(key), hasRight = right.has(key);
      const oldValue = hasLeft ? left.get(key) : 'Not present';
      const newValue = hasRight ? right.get(key) : 'Not present';
      const status = !hasLeft ? 'Added' : !hasRight ? 'Removed' : oldValue !== newValue ? 'Changed' : 'Unchanged';
      return { Key: key, Before: oldValue, After: newValue, State: status };
    });
  }

  function getCurrentReport() {
    return state.activeIndex >= 0 ? state.reports[state.activeIndex] : null;
  }

  function getEffectiveGuest(settings) {
    if (!settings) return null;
    if (settings.AllowInsecureGuestAuth_Policy !== null && settings.AllowInsecureGuestAuth_Policy !== undefined) return Number(settings.AllowInsecureGuestAuth_Policy);
    if (settings.GuestLogonsCmdlet !== null && settings.GuestLogonsCmdlet !== undefined) return settings.GuestLogonsCmdlet ? 1 : 0;
    if (settings.AllowInsecureGuestAuth_Runtime !== null && settings.AllowInsecureGuestAuth_Runtime !== undefined) return Number(settings.AllowInsecureGuestAuth_Runtime);
    return null;
  }

  function getSettingStates(snapshot) {
    const settings = snapshot?.MainSettings || {};
    const guest = getEffectiveGuest(settings);
    let signing = null;
    const hasPolicySigning = settings.PolicyRequireSecuritySignature !== null && settings.PolicyRequireSecuritySignature !== undefined;
    const hasRegistrySigning = settings.RequireSecuritySignature !== null && settings.RequireSecuritySignature !== undefined;
    if (hasPolicySigning && Number(settings.PolicyRequireSecuritySignature) === 1) signing = 'required';
    else if (settings.RequireSigningCmdlet === true) signing = 'required';
    else if (hasRegistrySigning && Number(settings.RequireSecuritySignature) === 1) signing = 'required';
    else if (settings.RequireSigningCmdlet === false || (hasRegistrySigning && Number(settings.RequireSecuritySignature) === 0)) signing = 'not-required';
    const bindings = settings.Binding || [];
    let binding = 'unavailable';
    if (bindings.length) binding = bindings.some((x) => Boolean(x.Enabled)) ? 'enabled' : 'disabled';
    return { guest, signing, binding, settings };
  }

  function stateClass(kind, value) {
    if (kind === 'guest') return value === 1 ? ['good', 'ALLOWED'] : value === 0 ? ['warn', 'BLOCKED'] : ['neutral', 'UNKNOWN'];
    if (kind === 'signing') return value === 'not-required' ? ['good', 'NOT REQUIRED'] : value === 'required' ? ['warn', 'REQUIRED'] : ['neutral', 'UNKNOWN'];
    return value === 'disabled' ? ['good', 'DISABLED'] : value === 'enabled' ? ['warn', 'ENABLED'] : ['neutral', 'UNAVAILABLE'];
  }

  function renderSettingRow(number, title, description, kind, beforeState, afterState, fieldDetails) {
    const [beforeClass, beforeLabel] = stateClass(kind, beforeState);
    const [afterClass, afterLabel] = stateClass(kind, afterState);
    return `<div class="setting-row">
      <div class="setting-no">${number}</div>
      <div class="setting-main"><strong>${esc(title)}</strong><small>${esc(description)}${fieldDetails ? `<br>${esc(fieldDetails)}` : ''}</small></div>
      <div class="setting-states"><span class="setting-state ${beforeClass}">B · ${beforeLabel}</span><span class="setting-state ${afterClass}">A · ${afterLabel}</span><small>BEFORE / AFTER</small></div>
    </div>`;
  }

  function renderSettings(report) {
    const before = getSettingStates(report.before);
    const after = getSettingStates(report.after);
    const bGuest = before.settings.AllowInsecureGuestAuth_Runtime;
    const aGuest = after.settings.AllowInsecureGuestAuth_Runtime;
    const guestDetail = `Runtime registry: ${valueText(bGuest)} → ${valueText(aGuest)}${after.settings.AllowInsecureGuestAuth_Policy !== null && after.settings.AllowInsecureGuestAuth_Policy !== undefined ? ` · Policy: ${valueText(after.settings.AllowInsecureGuestAuth_Policy)}` : ''}`;
    const signingDetail = `RequireSecuritySignature: ${valueText(before.settings.RequireSecuritySignature)} → ${valueText(after.settings.RequireSecuritySignature)} · EnableSecuritySignature: ${valueText(after.settings.EnableSecuritySignature)}`;
    const bindingDetail = `Detected adapters: ${before.settings.Binding?.length || 0} → ${after.settings.Binding?.length || 0}`;
    $('#settingsList').innerHTML = [
      renderSettingRow('01','SMB client signing requirement','First compatibility prerequisite; verifies whether outbound client signing is mandatory.','signing',before.signing,after.signing,signingDetail),
      renderSettingRow('02','Insecure guest authentication','Allows unauthenticated guest access to compatible SMB shares.','guest',before.guest,after.guest,guestDetail),
      renderSettingRow('03','Client for Microsoft Networks binding','Shows the binding state captured for network adapters.','binding',before.binding,after.binding,bindingDetail)
    ].join('');
    $('#settingsTimestamp').textContent = `CAPTURED ${formatDate(report.after?.CapturedAt || report.generatedAt)}`;
  }

  function renderMetrics(report) {
    const changes = report.changes || [];
    const changed = changes.filter((x) => String(x.State || '').toLowerCase() !== 'unchanged').length;
    const verified = report.summary.VerifiedActions ?? report.actions.filter((x) => String(x.Result || '').toUpperCase() === 'OK').length;
    const failed = report.summary.FailedActions ?? report.actions.filter((x) => String(x.Result || '').toUpperCase() === 'FAIL').length;
    const skipped = report.summary.SkippedActions ?? report.actions.filter((x) => String(x.Result || '').toUpperCase() === 'SKIP').length;
    $('#verifiedCount').textContent = numberText(verified);
    $('#verifiedNote').textContent = report.actions.length ? `${report.actions.length} operation(s) audited` : 'No action list in this report';
    $('#changedCount').textContent = numberText(changed);
    $('#changeNote').textContent = `${changes.length} fields compared`;
    $('#sampleCount').textContent = numberText(report.samples.length);
    $('#sampleNote').textContent = report.samples.length ? `First → last: ${formatDate(report.samples[0].CapturedAt)} / ${formatDate(report.samples[report.samples.length - 1].CapturedAt)}` : 'No sampling series attached';
    $('#issueCount').textContent = numberText(failed + skipped);
    $('#issueNote').textContent = `${failed} failed · ${skipped} skipped`;
  }

  function renderTimeline(report) {
    const samples = report.samples || [];
    if (!samples.length) {
      $('#timeline').innerHTML = '<div class="empty-state compact"><strong>No sampling series attached</strong><p>This report contains snapshots but no monitor timeline.</p></div>';
      return;
    }
    const subset = samples.length > 11 ? samples.filter((_, index) => index === 0 || index === samples.length - 1 || index % Math.ceil(samples.length / 10) === 0) : samples;
    $('#timeline').innerHTML = subset.map((sample, index) => {
      const state = getSettingStates(sample);
      const guest = state.guest === null ? 'guest n/a' : `guest ${state.guest ? 'allowed' : 'blocked'}`;
      const signing = state.signing || 'signing n/a';
      const binding = state.binding === 'unavailable' ? 'binding n/a' : `binding ${state.binding}`;
      const connectivity = sample.Connectivity || {};
      const gateway = connectivity.GatewayReachable === true ? 'gateway ICMP reply' : connectivity.GatewayReachable === false ? 'gateway ICMP no reply' : 'gateway ICMP n/a';
      const dns = connectivity.PublicDnsResolution === true ? 'configured DNS resolved' : connectivity.PublicDnsResolution === false ? 'configured DNS failed' : 'configured DNS n/a';
      const adapters = sample.Adapters || [];
      const upAdapters = adapters.filter((item) => String(item.Status || '').toLowerCase() === 'up').length;
      const services = sample.Services || [];
      const runningServices = services.filter((item) => String(item.Status || '').toLowerCase() === 'running').length;
      return `<div class="timeline-item"><span class="timeline-marker"></span><div class="timeline-content"><strong>${esc(formatDate(sample.CapturedAt) || `Sample ${index + 1}`)}</strong><p>${esc(guest)} · ${esc(signing)} · ${esc(binding)}</p><small>${esc(gateway)} · ${esc(dns)} · adapters ${upAdapters}/${adapters.length} up · services ${runningServices}/${services.length} running</small></div></div>`;
    }).join('');
  }

  function renderDiff(report) {
    const changes = report.changes || [];
    const filtered = state.filter === 'changed' ? changes.filter((x) => String(x.State || '').toLowerCase() !== 'unchanged') : changes;
    const changed = changes.filter((x) => String(x.State || '').toLowerCase() !== 'unchanged').length;
    $('#diffSummary').textContent = `${changed} changed / added / removed field(s) · ${changes.length} total observed`;
    if (!filtered.length) {
      $('#diffBody').innerHTML = '<tr><td colspan="4" class="table-empty">No fields match this filter.</td></tr>';
      return;
    }
    $('#diffBody').innerHTML = filtered.map((item) => {
      const status = String(item.State || 'Unchanged').toLowerCase();
      return `<tr><td>${esc(item.Key)}</td><td>${esc(valueText(item.Before))}</td><td>${esc(valueText(item.After))}</td><td><span class="result-pill ${esc(status)}">${esc(String(item.State || 'Unchanged').toUpperCase())}</span></td></tr>`;
    }).join('');
  }

  function renderSystem(report) {
    const snap = report.after || {};
    const env = snap.Environment || {};
    $('#computerName').textContent = env.ComputerName || snap.ComputerName || report.computerName || 'Unknown host';
    $('#systemSource').textContent = env.WindowsCaption ? 'SOURCE: WINDOWS APP REPORT' : 'SOURCE: PARTIAL / UNKNOWN';
    const items = [
      ['OPERATING SYSTEM', [env.WindowsCaption, env.WindowsVersion].filter(Boolean).join(' · ') || '—'],
      ['PROCESSOR', env.CPU || '—'],
      ['MEMORY', env.RAMGB ? `${env.RAMGB} GB` : '—'],
      ['ARCHITECTURE', env.OSArchitecture || '—'],
      ['BUILD', env.Build || '—'],
      ['POWERSHELL', [env.PowerShell, env.PowerShellEdition].filter(Boolean).join(' / ') || '—']
    ];
    $('#hardwareGrid').innerHTML = items.map(([label, value]) => `<div class="hardware-item"><span>${esc(label)}</span><strong title="${esc(value)}">${esc(value)}</strong></div>`).join('');

    const adapters = [...(snap.Adapters || [])].sort(sortByName);
    $('#adapterCount').textContent = adapters.length;
    $('#adapterList').innerHTML = adapters.length ? adapters.map((item) => {
      const up = String(item.Status || '').toLowerCase() === 'up';
      const secondary = [item.InterfaceDescription, item.IPv4Address, item.Gateway ? `GW ${item.Gateway}` : ''].filter(Boolean).join(' · ');
      return `<div class="adapter-item"><div class="adapter-main"><strong>${esc(item.Name || 'Network adapter')}</strong><small>${esc(secondary || item.MacAddress || 'No extra interface information')}</small></div><span class="detail-state ${up ? '' : 'down'}">${esc(item.Status || 'UNKNOWN')}</span></div>`;
    }).join('') : '<div class="table-empty">No adapter information was captured.</div>';

    const services = [...(snap.Services || [])].sort(sortByName);
    $('#serviceCount').textContent = services.length;
    $('#serviceList').innerHTML = services.length ? services.map((item) => {
      const running = String(item.Status || '').toLowerCase() === 'running';
      return `<div class="service-item"><div class="service-main"><strong>${esc(item.DisplayName || item.Name)}</strong><small>${esc(item.Name)} · ${esc(item.StartType || 'Unknown')}</small></div><span class="detail-state ${running ? '' : 'down'}">${esc(item.Status || 'UNKNOWN')}</span></div>`;
    }).join('') : '<div class="table-empty">No service information was captured.</div>';

    const connectivity = snap.Connectivity || {};
    const gatewayState = connectivity.GatewayReachable === true ? 'Reachable' : connectivity.GatewayReachable === false ? 'Unreachable' : 'Not detected';
    const dnsState = connectivity.PublicDnsResolution === true ? 'Resolved' : connectivity.PublicDnsResolution === false ? 'Failed' : 'Not tested';
    const facts = [
      ['DEFAULT GATEWAYS', valueText(connectivity.DefaultGateways)],
      ['DNS SERVERS', valueText(connectivity.DnsServers)],
      ['GATEWAY ICMP PROBE', gatewayState],
      ['CONFIGURED DNS TEST', dnsState]
    ];
    $('#connectivityFacts').innerHTML = facts.map(([label, value]) => `<div class="connectivity-fact"><span>${esc(label)}</span><strong>${esc(value)}</strong></div>`).join('');
    $('#connectivityState').textContent = connectivity.GatewayReachable === true && connectivity.PublicDnsResolution === true ? 'OK' : connectivity.GatewayReachable === false || connectivity.PublicDnsResolution === false ? 'CHECK' : 'N/A';

    const firewall = snap.Firewall || [];
    $('#firewallList').innerHTML = firewall.length ? firewall.map((item) => {
      const known = item.EnabledRules !== null && item.EnabledRules !== undefined;
      return `<div class="service-item"><div class="service-main"><strong>${esc(item.Group || 'Firewall group')}</strong><small>${esc(item.Note || (known ? `${item.EnabledRules} enabled rule(s)` : 'Provider unavailable'))}</small></div><span class="detail-state ${known ? '' : 'down'}">${known ? 'AVAILABLE' : 'N/A'}</span></div>`;
    }).join('') : '<div class="table-empty">No firewall information was captured.</div>';
  }

  function renderActions(report) {
    const actions = report.actions || [];
    if (!actions.length) {
      $('#actionList').innerHTML = '<article class="workflow-step empty-workflow"><span class="step-no">—</span><div><strong>No execution trace</strong><p>This report does not contain an option 3 action list. Import an ApplyReport JSON to inspect each verified operation.</p></div></article>';
      return;
    }
    $('#actionList').innerHTML = actions.map((action, index) => {
      const status = String(action.Result || 'UNKNOWN').toUpperCase();
      const className = status === 'OK' ? 'success' : status === 'FAIL' ? 'failure' : 'skipped';
      return `<article class="workflow-step ${className}"><span class="step-no">${String(index + 1).padStart(2, '0')}</span><div><strong>${esc(action.Name || action.Kind || 'Operation')}</strong><p>${esc(action.Details || 'No detail was included in this action record.')}</p><span class="action-result ${className}">${esc(status)} · ${esc(formatDate(action.CompletedAt))}</span></div></article>`;
    }).join('');
  }

  function renderReport(report) {
    if (!report) return;
    renderMetrics(report);
    renderSettings(report);
    renderTimeline(report);
    renderDiff(report);
    renderSystem(report);
    renderActions(report);
    const capture = report.generatedAt ? formatDate(report.generatedAt) : formatDate(report.after?.CapturedAt);
    $('#captureStatus').textContent = `${report.type} · ${report.computerName} · ${capture}`;
    toast(`Loaded ${report.fileName}`);
  }

  function populateSelector() {
    const select = $('#reportSelect');
    select.innerHTML = state.reports.map((report, index) => `<option value="${index}">${esc(report.fileName)} · ${esc(report.type)}</option>`).join('');
    select.disabled = !state.reports.length;
    if (state.reports.length) select.value = String(state.activeIndex);
  }

  async function importFiles(fileList) {
    const files = [...fileList].filter((file) => file.name.toLowerCase().endsWith('.json') || file.type === 'application/json');
    if (!files.length) { setError('Select one or more JSON report files.'); return; }
    let imported = 0;
    const errors = [];
    for (const file of files) {
      try {
        if (file.size > 10 * 1024 * 1024) throw new Error('Report is larger than the 10 MB safety limit.');
        const text = (await file.text()).replace(/^\uFEFF/, '');
        const parsed = JSON.parse(text);
        const report = normalizeReport(parsed, file.name);
        const existing = state.reports.findIndex((item) => item.fileName === file.name);
        if (existing >= 0) { state.reports[existing] = report; state.activeIndex = existing; }
        else { state.reports.push(report); state.activeIndex = state.reports.length - 1; }
        imported++;
      } catch (error) {
        errors.push(`${file.name}: ${error.message}`);
      }
    }
    $('#reportInput').value = '';
    if (imported) {
      populateSelector();
      renderReport(getCurrentReport());
      setError(errors.length ? errors.join(' | ') : '');
    } else {
      setError(errors.join(' | ') || 'No report could be imported.');
    }
  }

  function resetDashboard() {
    state.reports = [];
    state.activeIndex = -1;
    $('#reportSelect').innerHTML = '<option>No report loaded</option>';
    $('#reportSelect').disabled = true;
    $('#captureStatus').textContent = 'Waiting for a real report from the Windows app';
    $('#verifiedCount').textContent = $('#changedCount').textContent = $('#sampleCount').textContent = $('#issueCount').textContent = '—';
    $('#verifiedNote').textContent = 'Waiting for report';
    $('#changeNote').textContent = 'Before / after diff';
    $('#sampleNote').textContent = 'Captured by the app';
    $('#issueNote').textContent = 'Action verification';
    $('#settingsList').innerHTML = '<div class="empty-state"><span class="empty-pulse"></span><strong>No configuration loaded</strong><p>Import an application report to see the current state.</p></div>';
    $('#timeline').innerHTML = '<div class="empty-state compact"><strong>Nothing to plot yet</strong><p>Import a monitor or apply report.</p></div>';
    $('#diffBody').innerHTML = '<tr><td colspan="4" class="table-empty">Import a JSON report to populate the comparison.</td></tr>';
    $('#diffSummary').textContent = 'No comparison available';
    $('#computerName').textContent = 'No host loaded';
    $('#systemSource').textContent = 'SOURCE: WAITING';
    $('#adapterCount').textContent = $('#serviceCount').textContent = '0';
    $('#connectivityState').textContent = '—';
    $('#adapterList').innerHTML = $('#serviceList').innerHTML = $('#connectivityFacts').innerHTML = $('#firewallList').innerHTML = '<div class="table-empty">No data.</div>';
    $('#actionList').innerHTML = '<article class="workflow-step empty-workflow"><span class="step-no">01</span><div><strong>Pre-check & backup</strong><p>Action details appear here after importing an ApplyReport JSON.</p></div></article>';
    renderBrowserFacts();
    setError('');
    toast('Dashboard reset. No local reports are retained.');
  }

  function bindEvents() {
    $('#reportInput').addEventListener('change', (event) => importFiles(event.target.files));
    $('#clearReports').addEventListener('click', resetDashboard);
    $('#reportSelect').addEventListener('change', (event) => {
      state.activeIndex = Number(event.target.value);
      renderReport(getCurrentReport());
    });
    document.querySelectorAll('.filter-tab').forEach((button) => button.addEventListener('click', () => {
      state.filter = button.dataset.filter;
      document.querySelectorAll('.filter-tab').forEach((item) => item.classList.toggle('active', item === button));
      if (getCurrentReport()) renderDiff(getCurrentReport());
    }));
    $('#importPanel').addEventListener('dragover', (event) => { event.preventDefault(); $('#importPanel').classList.add('dragging'); });
    $('#importPanel').addEventListener('dragleave', (event) => { if (!$('#importPanel').contains(event.relatedTarget)) $('#importPanel').classList.remove('dragging'); });
    $('#importPanel').addEventListener('drop', (event) => { event.preventDefault(); $('#importPanel').classList.remove('dragging'); importFiles(event.dataTransfer.files); });
    $('#year').textContent = new Date().getFullYear();
    document.addEventListener('keydown', (event) => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'o') { event.preventDefault(); $('#reportInput').click(); }
    });
  }

  setLinks();
  renderBrowserFacts();
  bindEvents();
})();
