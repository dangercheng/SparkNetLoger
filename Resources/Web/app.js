/* No dependencies; this file also exposes pure model functions for Node tests. */
(function (root) {
  'use strict';
  const messages = {
    "en": {
      "live": "Live Logs",
      "connecting": "Connecting…",
      "retrying": "Disconnected. Retrying; if the address changed, open the new URL shown in the app.",
      "syncing": "Connected · Syncing",
      "connected": "Connected · Receiving logs",
      "closed": "Live logging was turned off in the app",
      "expand": "Expand filters",
      "collapse": "Collapse filters",
      "autoOn": "Auto-scroll: On",
      "autoPaused": "Auto-scroll: On (following paused)",
      "autoOff": "Auto-scroll: Off",
      "bottom": "Scroll to bottom",
      "toRaw": "Switch to plain text",
      "toFormatted": "Switch to formatted logs",
      "copy": "Copy all",
      "copied": "Copied",
      "copyFailed": "Copy failed. Select the log text and copy manually.",
      "clear": "Clear logs",
      "search": "Search logs",
      "searchHint": "Search message, tag, source location or context",
      "levels": "Log levels",
      "tags": "Tags",
      "count": "{visible} / {total} logs",
      "empty": "Waiting for logs from the app",
      "noMatch": "No logs match the filters",
      "hintFormatted": "Latest 2000 logs · Click a log to expand context",
      "hintRaw": "Latest 2000 logs · Select text or copy all filtered logs",
      "logList": "Log list",
      "rawLogs": "Plain-text logs",
      "language": "Language"
    },
    "zh": {
      "live": "实时日志",
      "connecting": "正在连接…",
      "retrying": "连接中断，正在重试；地址变化时请打开 App 中的新网址",
      "syncing": "已连接 · 正在同步",
      "connected": "已连接 · 实时接收",
      "closed": "App 已关闭实时日志",
      "expand": "展开筛选",
      "collapse": "收起筛选",
      "autoOn": "自动滚动：开",
      "autoPaused": "自动滚动：开（暂停跟随）",
      "autoOff": "自动滚动：关",
      "bottom": "滚动到底部",
      "toRaw": "切换原生日志",
      "toFormatted": "切换格式化日志",
      "copy": "复制全部",
      "copied": "已复制",
      "copyFailed": "复制失败，请选择日志文字手动复制",
      "clear": "清空日志",
      "search": "搜索日志",
      "searchHint": "搜索正文、Tag、文件行号或 context",
      "levels": "日志等级",
      "tags": "Tag",
      "count": "{visible} / {total} 条日志",
      "empty": "等待 App 输出日志",
      "noMatch": "没有符合筛选条件的日志",
      "hintFormatted": "仅保留最近 2000 条 · 点击日志展开 context",
      "hintRaw": "仅保留最近 2000 条 · 可选择文字或复制全部筛选结果",
      "logList": "日志列表",
      "rawLogs": "原生日志",
      "language": "语言"
    }
  };
  function resolveLanguage(saved, preferred = 'en') {
    return saved === 'en' || saved === 'zh' ? saved : (preferred.toLowerCase().startsWith('zh') ? 'zh' : 'en');
  }
  function translate(language, key, values = {}) {
    const text = messages[language]?.[key] ?? messages.en[key] ?? key;
    return text.replace(/\{(\w+)\}/g, (match, name) => values[name] ?? match);
  }
  const palette = ['#86c9f4', '#e8a3e8', '#86dbb4', '#edc180', '#aeb5ff', '#edaaa1', '#8dd8d8', '#d0da8b'];
  function tagColor(tag) { let hash = 2166136261; for (const char of tag) hash = Math.imul(hash ^ char.codePointAt(0), 16777619); return palette[(hash >>> 0) % palette.length]; }
  function formatTime(timestamp) { return new Date(timestamp).toLocaleTimeString(undefined, {hour12:false, hour:'2-digit', minute:'2-digit', second:'2-digit', fractionalSecondDigits:3}); }
  function sourceLocation(entry) { return entry.file && Number.isSafeInteger(entry.line) ? entry.file + ':' + entry.line : ''; }
  function matches(entry, levels, excludedTags, query) {
    return levels.has(entry.level) && !excludedTags.has(entry.tag) &&
      (!query || [entry.message, entry.tag, sourceLocation(entry), JSON.stringify(entry.context)].join(' ').toLocaleLowerCase().includes(query.toLocaleLowerCase()));
  }
  function formatLogs(entries) {
    return entries.map(entry => {
      const location = sourceLocation(entry);
      const line = `${formatTime(entry.timestamp)} [${entry.level.toUpperCase()}] [${entry.tag}]${location ? ` [${location}]` : ''} ${entry.message}`;
      return entry.context && Object.keys(entry.context).length ? line + '\n' + JSON.stringify(entry.context, null, 2) : line;
    }).join('\n\n');
  }
  class Store {
    constructor() { this.entries = []; this.session = null; this.maxSequence = 0; }
    begin(session) { if (this.session !== session) { this.session = session; this.entries = []; this.maxSequence = 0; } }
    add(entries) {
      for (const entry of entries) {
        if (entry.sessionID !== this.session || !Number.isSafeInteger(entry.sequence) || entry.sequence <= this.maxSequence) continue;
        this.maxSequence = entry.sequence; this.entries.push(entry);
      }
      this.entries = this.entries.slice(-2000);
    }
    clear() { this.entries = []; }
  }
  const api = { tagColor, formatTime, matches, Store, formatLogs, sourceLocation, messages, resolveLanguage, translate };
  if (typeof module !== 'undefined') module.exports = api;
  if (typeof document === 'undefined') return;
  const $ = id => document.getElementById(id);
  let savedLanguage;
  try { savedLanguage = localStorage.getItem('SparkNetLoger.language'); } catch (_) {}
  let language = resolveLanguage(savedLanguage, navigator.language || 'en');
  let connectionKey = 'connecting', copyKey = '';
  const t = (key, values) => translate(language, key, values);
  function setConnection(key) { connectionKey = key; $('status').textContent = t(key); }
  function setCopyStatus(key) { copyKey = key; $('copy-status').textContent = key ? t(key) : ''; }
  function applyLanguage() {
    document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en';
    document.title = 'SparkNetLoger · ' + t('live');
    for (const element of document.querySelectorAll('[data-i18n]')) element.textContent = t(element.dataset.i18n);
    $('language').value = language; $('language').setAttribute('aria-label', t('language'));
    $('search').placeholder = t('searchHint');
    formattedViewport.setAttribute('aria-label', t('logList')); raw.setAttribute('aria-label', t('rawLogs'));
    $('toggle-filters').textContent = t($('filters').hidden ? 'expand' : 'collapse');
    $('toggle-raw').textContent = t(plain ? 'toFormatted' : 'toRaw');
    $('view-hint').textContent = t(plain ? 'hintRaw' : 'hintFormatted');
    setConnection(connectionKey); setCopyStatus(copyKey); updateScrollButton();
  }
  const store = new Store(), levels = new Set(['error', 'warning', 'info', 'debug']), excludedTags = new Set();
  let query = '', autoScroll = true, socket, stopped = false, retries = 0, timer, scheduled = false;
  let historyLoading = false, historyEntries = [];
  const expanded = new Set();
  const formattedViewport = $('log-viewport'), raw = $('raw-logs'), followDistance = 100;
  let viewport = formattedViewport, plain = false, restoreTop = null;
  const positions = {formatted: 0, plain: 0};
  let copyTimer;
  let rawRecords = [];
  function updateRawText(entries) {
    let offset = 0;
    const records = entries.map(entry => {
      const text = formatLogs([entry]);
      const record = {key: entry.sessionID + ':' + entry.sequence, offset, text};
      offset += text.length + 2;
      return record;
    });
    const text = records.map(record => record.text).join('\n\n');
    const nextByKey = new Map(records.map(record => [record.key, record]));
    const remap = index => {
      const record = rawRecords.find((record, i) => index < (rawRecords[i + 1]?.offset ?? Infinity));
      const next = record && nextByKey.get(record.key);
      return next ? Math.min(text.length, next.offset + Math.min(index - record.offset, record.text.length + 2)) : 0;
    };
    if (raw.value !== text) {
      const start = remap(raw.selectionStart), end = remap(raw.selectionEnd), direction = raw.selectionDirection;
      raw.value = text;
      raw.setSelectionRange(start, end, direction);
    }
    rawRecords = records;
  }
  function copyFallback(text) {
    const focused = document.activeElement, top = viewport.scrollTop;
    const selection = [raw.selectionStart, raw.selectionEnd, raw.selectionDirection];
    const buffer = document.createElement('textarea');
    buffer.className = 'clipboard-buffer'; buffer.value = text; buffer.readOnly = true;
    document.body.append(buffer);
    try { buffer.select(); return document.execCommand('copy'); }
    finally {
      buffer.remove(); focused?.focus({preventScroll:true});
      raw.setSelectionRange(...selection); setScrollPosition(top);
    }
  }
  let following = true, lastScrollTop = viewport.scrollTop;
  function updateScrollButton() {
    $('scroll').textContent = t(autoScroll ? (following ? 'autoOn' : 'autoPaused') : 'autoOff');
    $('scroll').setAttribute('aria-pressed', String(autoScroll));
  }
  function readScrollPosition() {
    // Our own writes also emit delayed scroll events. Only react to a changed position.
    if (viewport.scrollTop === lastScrollTop) return;
    following = Math.max(0, viewport.scrollHeight - viewport.clientHeight - viewport.scrollTop) <= followDistance;
    updateScrollButton();
    lastScrollTop = viewport.scrollTop;
  }
  function setScrollPosition(top) {
    viewport.scrollTop = top;
    lastScrollTop = viewport.scrollTop;
  }
  function scrollToBottom() {
    following = true;
    updateScrollButton();
    setScrollPosition(viewport.scrollHeight);
  }
  for (const container of [formattedViewport, raw]) {
    container.addEventListener('scroll', () => { if (container === viewport) readScrollPosition(); }, {passive:true});
  }
  function checkbox(parent, value, checked, callback, color) {
    const label = document.createElement('label'), input = document.createElement('input'), text = document.createElement('span');
    input.type = 'checkbox'; input.checked = checked; input.addEventListener('change', () => callback(input.checked));
    text.textContent = value; if (color) text.style.color = color;
    label.append(input, text); parent.append(label);
  }
  for (const level of levels) checkbox($('levels'), level.toUpperCase(), true, checked => { checked ? levels.add(level) : levels.delete(level); renderSoon(); });
  function span(className, text) { const el = document.createElement('span'); el.className = className; el.textContent = text; return el; }
  function renderSoon() { if (scheduled) return; scheduled = true; requestAnimationFrame(render); }
  function render() {
    scheduled = false;
    // Capture user movement before changing content, even if its scroll event is pending.
    readScrollPosition();
    const oldY = restoreTop ?? viewport.scrollTop, shouldFollow = autoScroll && following;
    restoreTop = null;
    // Read the current DOM before rebuilding; native toggle events may still be queued.
    for (const row of $('logs').children) {
      row.open ? expanded.add(row.dataset.key) : expanded.delete(row.dataset.key);
    }
    const tags = [...new Set(store.entries.map(e => e.tag))].sort();
    // Keep selections when a tag briefly leaves the bounded history window.
    $('tags').replaceChildren(Object.assign(document.createElement('legend'), {textContent: t('tags')}));
    for (const tag of tags) checkbox($('tags'), tag, !excludedTags.has(tag), checked => { checked ? excludedTags.delete(tag) : excludedTags.add(tag); renderSoon(); }, tagColor(tag));
    const visible = store.entries.filter(e => matches(e, levels, excludedTags, query));
    if (plain) { updateRawText(visible); } else {
      const fragment = document.createDocumentFragment();
      for (const entry of visible) {
        const row = document.createElement('details'), summary = document.createElement('summary');
        const key = entry.sessionID + ':' + entry.sequence;
        row.dataset.key = key;
        row.className = ['error', 'warning', 'info', 'debug'].includes(entry.level) ? entry.level : 'debug';
        row.open = expanded.has(key);
        const tag = span('badge', entry.tag); tag.style.color = tagColor(entry.tag);
        const time = formatTime(entry.timestamp);
        summary.append(span('time', time), span('level', entry.level.toUpperCase()), tag, span('message', entry.message));
        const location = sourceLocation(entry);
        if (location) summary.insertBefore(span('source', location), summary.lastChild);
        const context = document.createElement('pre'); context.textContent = JSON.stringify(entry.context, null, 2);
        row.append(summary, context); fragment.append(row);
      }
      $('logs').replaceChildren(fragment);
    }
    const alive = new Set(store.entries.map(e => e.sessionID + ':' + e.sequence));
    for (const key of expanded) if (!alive.has(key)) expanded.delete(key);
    $('count').textContent = t('count', {visible: visible.length, total: store.entries.length});
    $('empty').hidden = visible.length > 0;
    $('empty').textContent = t(store.entries.length ? 'noMatch' : 'empty');
    raw.placeholder = $('empty').textContent;
    $('copy-logs').disabled = visible.length === 0;
    const selecting = plain && document.activeElement === raw && raw.selectionStart !== raw.selectionEnd;
    setScrollPosition(shouldFollow && visible.length && !selecting ? viewport.scrollHeight : oldY);
  }
  $('toggle-filters').addEventListener('click', () => {
    readScrollPosition();
    const oldY = viewport.scrollTop, shouldFollow = autoScroll && following;
    const filters = $('filters');
    filters.hidden = !filters.hidden;
    $('toggle-filters').textContent = t(filters.hidden ? 'expand' : 'collapse');
    $('toggle-filters').setAttribute('aria-expanded', String(!filters.hidden));
    setScrollPosition(shouldFollow ? viewport.scrollHeight : oldY);
  });
  $('toggle-raw').addEventListener('click', () => {
    readScrollPosition();
    positions[plain ? 'plain' : 'formatted'] = viewport.scrollTop;
    plain = !plain;
    formattedViewport.hidden = plain; raw.hidden = !plain;
    viewport = plain ? raw : formattedViewport;
    lastScrollTop = viewport.scrollTop;
    restoreTop = positions[plain ? 'plain' : 'formatted'];
    $('toggle-raw').textContent = t(plain ? 'toFormatted' : 'toRaw');
    $('toggle-raw').setAttribute('aria-pressed', String(plain));
    $('scroll-bottom').setAttribute('aria-controls', viewport.id);
    $('copy-logs').hidden = !plain;
    setCopyStatus('');
    $('view-hint').textContent = t(plain ? 'hintRaw' : 'hintFormatted');
    renderSoon();
  });
  $('copy-logs').addEventListener('click', async () => {
    const text = formatLogs(store.entries.filter(e => matches(e, levels, excludedTags, query)));
    if (!text) return;
    let copied = false;
    try {
      if (navigator.clipboard?.writeText) {
        try { await navigator.clipboard.writeText(text); copied = true; } catch (_) { copied = copyFallback(text); }
      } else { copied = copyFallback(text); }
    } catch (_) { copied = false; }
    clearTimeout(copyTimer);
    setCopyStatus(copied ? 'copied' : 'copyFailed');
    if (copied) copyTimer = setTimeout(() => { setCopyStatus(''); }, 2000);
  });
  $('search').addEventListener('input', event => { query = event.target.value; renderSoon(); });
  $('scroll').addEventListener('click', () => {
    autoScroll = !autoScroll;
    if (autoScroll) scrollToBottom(); else updateScrollButton();
  });
  $('scroll-bottom').addEventListener('click', scrollToBottom);
  $('clear').addEventListener('click', () => {
    store.clear(); expanded.clear(); following = true;
    positions.formatted = positions.plain = 0; setCopyStatus('');
    updateScrollButton(); lastScrollTop = viewport.scrollTop; renderSoon();
  });
  function reconnect() {
    if (stopped) return;
    const delay = [1000, 2000, 4000, 8000, 10000][Math.min(retries++, 4)];
    setConnection('retrying');
    clearTimeout(timer); timer = setTimeout(connect, delay);
  }
  async function connect() {
    if (stopped) return;
    historyLoading = false; historyEntries = [];
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 5000);
      let response;
      try { response = await fetch('/config.json', {cache:'no-store', signal: controller.signal}); }
      finally { clearTimeout(timeout); }
      if (!response.ok) throw new Error('config');
      const config = await response.json();
      socket = new WebSocket('ws://' + location.hostname + ':' + config.webSocketPort);
      const current = socket;
      socket.onopen = () => { if (current !== socket) return; retries = 0; setConnection('syncing'); };
      socket.onmessage = event => {
        if (current !== socket || stopped) return;
        let packet; try { packet = JSON.parse(event.data); } catch (_) { return; }
        if (packet.version !== 1) return;
        if (packet.type === 'closed') {
          stopped = true; clearTimeout(timer); setConnection('closed'); socket.close(); return;
        }
        if (packet.type === 'suspended') { socket.close(); return; }
        if (packet.type === 'historyStart') {
          store.begin(packet.sessionID); historyLoading = true; historyEntries = [];
        } else if (packet.type === 'logs' && Array.isArray(packet.entries)) {
          if (historyLoading) historyEntries.push(...packet.entries);
          else { store.add(packet.entries); renderSoon(); }
        } else if (packet.type === 'historyEnd') {
          historyLoading = false;
          // Sort once so history and any in-flight broadcast cannot create a sequence gap.
          store.add(historyEntries.sort((a,b) => a.sequence - b.sequence)); historyEntries = [];
          setConnection('connected'); renderSoon();
        }
      };
      socket.onclose = () => { if (current === socket) reconnect(); };
      socket.onerror = () => current.close();
    } catch (_) { reconnect(); }
  }
  document.addEventListener('visibilitychange', () => { if (!document.hidden && !stopped && socket?.readyState === WebSocket.CLOSED) { clearTimeout(timer); connect(); } });
  $('language').addEventListener('change', () => {
    readScrollPosition();
    const oldY = viewport.scrollTop;
    language = resolveLanguage($('language').value);
    try { localStorage.setItem('SparkNetLoger.language', language); } catch (_) {}
    applyLanguage(); setScrollPosition(oldY); renderSoon();
  });
  applyLanguage(); renderSoon(); connect();
})(typeof window === 'undefined' ? globalThis : window);
