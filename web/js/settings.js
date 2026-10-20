// State Management
function loadCachedConfig() {
  try {
    const cached = localStorage.getItem("windowassist_config");
    if (cached) {
      const parsed = JSON.parse(cached);
      if (parsed && typeof parsed === "object") {
        return Object.assign({}, window.DEFAULT_CONFIG, parsed);
      }
    }
  } catch (e) {}
  return JSON.parse(JSON.stringify(window.DEFAULT_CONFIG));
}

function saveConfigToStorage() {
  try {
    localStorage.setItem("windowassist_config", JSON.stringify(currentConfig));
  } catch (e) {}
}

let currentConfig = loadCachedConfig();
let currentLang = currentConfig.language || "en";
let activeTabId = "tab-hotkeys";
let currentSearchQuery = "";
let recordingTarget = null; // { actionKey: string }
let isNumLockHeld = false;  // Tracks NumLock state during recording

const HOTKEY_ACTIONS = [
  { key: "move_window_prefix", group: "sys", i18nTitle: "act_move_window_prefix", i18nDesc: "act_move_window_prefix_desc" },
  { key: "overview_toggle", group: "overview", i18nTitle: "act_overview_toggle", i18nDesc: "act_overview_toggle_desc" },
  { key: "pocket_toggle_window", group: "pocket", i18nTitle: "act_pocket_toggle_window", i18nDesc: "act_pocket_toggle_window_desc" },
  { key: "pocket_cycle", group: "pocket", i18nTitle: "act_pocket_cycle", i18nDesc: "act_pocket_cycle_desc" },
  { key: "pocket_summon", group: "pocket", i18nTitle: "act_pocket_summon", i18nDesc: "act_pocket_summon_desc" },
  
  // Workspaces 1..9
  { key: "workspace_switch_1", group: "workspaces", i18nTitle: "act_workspace_switch", i18nDesc: "act_workspace_switch_desc", param: 1 },
  { key: "workspace_switch_2", group: "workspaces", i18nTitle: "act_workspace_switch", i18nDesc: "act_workspace_switch_desc", param: 2 },
  { key: "workspace_switch_3", group: "workspaces", i18nTitle: "act_workspace_switch", i18nDesc: "act_workspace_switch_desc", param: 3 },
  { key: "workspace_switch_4", group: "workspaces", i18nTitle: "act_workspace_switch", i18nDesc: "act_workspace_switch_desc", param: 4 },
  { key: "workspace_switch_5", group: "workspaces", i18nTitle: "act_workspace_switch", i18nDesc: "act_workspace_switch_desc", param: 5 },
  { key: "workspace_switch_6", group: "workspaces", i18nTitle: "act_workspace_switch", i18nDesc: "act_workspace_switch_desc", param: 6 },
  { key: "workspace_switch_7", group: "workspaces", i18nTitle: "act_workspace_switch", i18nDesc: "act_workspace_switch_desc", param: 7 },
  { key: "workspace_switch_8", group: "workspaces", i18nTitle: "act_workspace_switch", i18nDesc: "act_workspace_switch_desc", param: 8 },
  { key: "workspace_switch_9", group: "workspaces", i18nTitle: "act_workspace_switch", i18nDesc: "act_workspace_switch_desc", param: 9 },

  // Move window 1..9
  { key: "workspace_move_1", group: "workspaces", i18nTitle: "act_workspace_move", i18nDesc: "act_workspace_move_desc", param: 1 },
  { key: "workspace_move_2", group: "workspaces", i18nTitle: "act_workspace_move", i18nDesc: "act_workspace_move_desc", param: 2 },
  { key: "workspace_move_3", group: "workspaces", i18nTitle: "act_workspace_move", i18nDesc: "act_workspace_move_desc", param: 3 },
  { key: "workspace_move_4", group: "workspaces", i18nTitle: "act_workspace_move", i18nDesc: "act_workspace_move_desc", param: 4 },
  { key: "workspace_move_5", group: "workspaces", i18nTitle: "act_workspace_move", i18nDesc: "act_workspace_move_desc", param: 5 },
  { key: "workspace_move_6", group: "workspaces", i18nTitle: "act_workspace_move", i18nDesc: "act_workspace_move_desc", param: 6 },
  { key: "workspace_move_7", group: "workspaces", i18nTitle: "act_workspace_move", i18nDesc: "act_workspace_move_desc", param: 7 },
  { key: "workspace_move_8", group: "workspaces", i18nTitle: "act_workspace_move", i18nDesc: "act_workspace_move_desc", param: 8 },
  { key: "workspace_move_9", group: "workspaces", i18nTitle: "act_workspace_move", i18nDesc: "act_workspace_move_desc", param: 9 },

  // Workspaces relative
  { key: "workspace_prev", group: "workspaces", i18nTitle: "act_workspace_prev", i18nDesc: "act_workspace_prev_desc" },
  { key: "workspace_next", group: "workspaces", i18nTitle: "act_workspace_next", i18nDesc: "act_workspace_next_desc" },

  // Window operations
  { key: "window_close", group: "window", i18nTitle: "act_window_close", i18nDesc: "act_window_close_desc" },
  { key: "window_minimize", group: "window", i18nTitle: "act_window_minimize", i18nDesc: "act_window_minimize_desc" },
  { key: "window_pin", group: "window", i18nTitle: "act_window_pin", i18nDesc: "act_window_pin_desc" },
  { key: "window_mouse_modifier", group: "window", i18nTitle: "act_window_mouse_modifier", i18nDesc: "act_window_mouse_modifier_desc" },

  // System
  { key: "open_settings", group: "sys", i18nTitle: "act_open_settings", i18nDesc: "act_open_settings_desc" },
  { key: "reload_script", group: "sys", i18nTitle: "act_reload_script", i18nDesc: "act_reload_script_desc" },
  { key: "panic_key", group: "sys", i18nTitle: "act_panic_key", i18nDesc: "act_panic_key_desc" },
  { key: "alt_tab", group: "sys", i18nTitle: "act_alt_tab", i18nDesc: "act_alt_tab_desc" }
];

function getPropertyByPath(obj, path) {
  const parts = path.split('.');
  let current = obj;
  for (const part of parts) {
    if (current == null) return undefined;
    current = current[part];
  }
  return current;
}

function setPropertyByPath(obj, path, value) {
  const parts = path.split('.');
  let current = obj;
  for (let i = 0; i < parts.length - 1; i++) {
    const part = parts[i];
    if (!current[part] || typeof current[part] !== 'object') {
      current[part] = {};
    }
    current = current[part];
  }
  current[parts[parts.length - 1]] = value;
}

function sendToAhk(action, payload) {
  if (action !== "SETTINGS_READY" && action !== "START_KEY_RECORDING" && action !== "STOP_KEY_RECORDING") {
    setSavingStatus(true);
    setTimeout(() => setSavingStatus(false), 250);
  }
  if (window.ahk && window.ahk.send) {
    window.ahk.send(Object.assign({ action: action }, payload));
  }
}

function setSavingStatus(isSaving) {
  const statusEl = document.getElementById("save-status");
  const textEl = document.getElementById("save-text");
  if (!statusEl || !textEl) return;
  if (isSaving) {
    statusEl.classList.add("saving");
    textEl.textContent = t("savingStatus");
  } else {
    statusEl.classList.remove("saving");
    textEl.textContent = t("savedStatus");
  }
}

function t(key, params) {
  if (!key) return "";
  const dict = (window.I18N && window.I18N[currentLang]) || (window.I18N && window.I18N["en"]) || {};
  let text = (key in dict) ? dict[key] : key;
  if (params && typeof text === 'string') {
    for (const p in params) {
      text = text.replace(new RegExp(`\\{${p}\\}`, 'g'), params[p]);
    }
  }
  return text;
}

function toggleLangDropdown(e) {
  if (e) e.stopPropagation();
  const popup = document.getElementById("lang-popup");
  const btn = document.getElementById("lang-globe-btn");
  if (!popup) return;
  const isShown = popup.classList.toggle("show");
  if (btn) btn.classList.toggle("active", isShown);
}

function closeLangDropdown() {
  const popup = document.getElementById("lang-popup");
  const btn = document.getElementById("lang-globe-btn");
  if (popup) popup.classList.remove("show");
  if (btn) btn.classList.remove("active");
}

function selectLanguage(lang, e) {
  if (e) e.stopPropagation();
  closeLangDropdown();
  setLanguage(lang);
}

document.addEventListener("click", (e) => {
  const wrapper = document.getElementById("lang-dropdown-wrapper");
  if (wrapper && !wrapper.contains(e.target)) {
    closeLangDropdown();
  }
});

function setLanguage(lang) {
  if (lang !== "ru" && lang !== "en") return;
  currentLang = lang;
  currentConfig.language = lang;
  saveConfigToStorage();

  const currentLabel = document.getElementById("lang-current-label");
  if (currentLabel) {
    currentLabel.textContent = lang === "ru" ? "РУС" : "ENG";
  }

  const optRu = document.getElementById("lang-opt-ru");
  const optEn = document.getElementById("lang-opt-en");
  if (optRu) optRu.classList.toggle("active", lang === "ru");
  if (optEn) optEn.classList.toggle("active", lang === "en");

  document.querySelectorAll("[data-i18n]").forEach(el => {
    const key = el.getAttribute("data-i18n");
    el.textContent = t(key);
  });

  document.querySelectorAll("[data-i18n-ph]").forEach(el => {
    const key = el.getAttribute("data-i18n-ph");
    el.placeholder = t(key);
  });

  document.querySelectorAll("[data-i18n-title]").forEach(el => {
    const key = el.getAttribute("data-i18n-title");
    el.title = t(key);
  });

  updatePageTitle();
  renderHotkeysList();
  sendToAhk("SET_SETTING", { key: "language", value: lang });
}

function switchTab(tabId) {
  activeTabId = tabId;
  document.querySelectorAll(".nav-item").forEach(item => {
    item.classList.toggle("active", item.getAttribute("data-tab") === tabId);
  });
  document.querySelectorAll(".tab-panel").forEach(panel => {
    panel.classList.toggle("active", panel.id === tabId);
  });
  updatePageTitle();
}

function updatePageTitle() {
  const titleEl = document.getElementById("page-title");
  if (!titleEl) return;
  if (activeTabId === "tab-hotkeys") titleEl.textContent = t("tabHotkeysTitle");
  else if (activeTabId === "tab-general") titleEl.textContent = t("tabGeneralTitle");
  else if (activeTabId === "tab-appearance") titleEl.textContent = t("tabAppearanceTitle");
}

function syncFormValues() {
  const elFontSize = document.getElementById("gen_osd_fontSize");
  if (elFontSize) elFontSize.value = currentConfig.general.osd.fontSize;
  const elPos = document.getElementById("gen_osd_position");
  if (elPos) elPos.value = currentConfig.general.osd.position;
  const elPosY = document.getElementById("gen_osd_posYPercent");
  if (elPosY) elPosY.value = currentConfig.general.osd.posYPercent;
  const elDelay = document.getElementById("gen_osd_hideDelayMs");
  if (elDelay) elDelay.value = currentConfig.general.osd.hideDelayMs;
  onOsdPositionChange(currentConfig.general.osd.position, false);

  const elTbAuto = document.getElementById("gen_tb_autoHide");
  if (elTbAuto) elTbAuto.checked = !!currentConfig.general.titleBar.autoHide;
  const elTbDark = document.getElementById("gen_tb_darkTheme");
  if (elTbDark) elTbDark.checked = !!currentConfig.general.titleBar.darkTheme;

  document.getElementById("gen_tb_hideTaskList").checked = !!currentConfig.general.taskbar.hideTaskList;

  document.getElementById("app_animationDurationMs").value = currentConfig.appearance.animationDurationMs;

  syncColorControl("appearance.colors.workspaceBorderHover", "col_workspaceBorderHover", "text_col_wsBorder", "box_col_wsBorder");
  syncColorControl("appearance.colors.pocketTheme", "col_pocketTheme", "text_col_pocket", "box_col_pocket");
  syncColorControl("appearance.colors.windowDragPulse", "col_windowDragPulse", "text_col_dragPulse", "box_col_dragPulse");
  const elDragPulseWidth = document.getElementById("app_windowDragPulseWidth");
  if (elDragPulseWidth) elDragPulseWidth.value = currentConfig.appearance.colors.windowDragPulseWidth || 3;
  syncColorControl("appearance.colors.pocketWindowBorder", "col_pocketWindowBorder", "text_col_pocketBorder", "box_col_pocketBorder");
  document.getElementById("app_pocketBorderWidth").value = currentConfig.appearance.colors.pocketBorderWidth;

  syncProfileSelect();
  renderHotkeysList();
  updateResetButtonsStatus();
}

function syncColorControl(configPath, inputId, textId, boxId) {
  const val = getPropertyByPath(currentConfig, configPath) || "#000000";
  const inp = document.getElementById(inputId);
  const txt = document.getElementById(textId);
  const box = document.getElementById(boxId);
  if (inp) inp.value = val;
  if (txt) txt.value = val.toUpperCase();
  if (box) box.style.backgroundColor = val;
}

function onOsdPositionChange(val, save = true) {
  const rowCustom = document.getElementById("row_osd_posYPercent");
  if (rowCustom) {
    rowCustom.style.display = (val === "custom") ? "flex" : "none";
  }
  if (save) {
    updateSetting("general.osd.position", val);
  }
}

function onColorInput(configPath, hex) {
  setPropertyByPath(currentConfig, configPath, hex);
  saveConfigToStorage();
  syncFormValues();
  sendToAhk("SET_SETTING", { key: configPath, value: hex });
}

function onHexTextInput(configPath, val) {
  if (/^#[0-9A-Fa-f]{6}$/.test(val)) {
    setPropertyByPath(currentConfig, configPath, val);
    saveConfigToStorage();
    syncFormValues();
    sendToAhk("SET_SETTING", { key: configPath, value: val });
  }
}

function updateSetting(path, val) {
  setPropertyByPath(currentConfig, path, val);
  saveConfigToStorage();
  updateResetButtonsStatus();
  sendToAhk("SET_SETTING", { key: path, value: val });
}

function resetField(path) {
  const defVal = getPropertyByPath(window.DEFAULT_CONFIG, path);
  if (defVal === undefined) return;
  setPropertyByPath(currentConfig, path, JSON.parse(JSON.stringify(defVal)));
  if (path === "general.osd.position") {
    onOsdPositionChange(defVal, false);
  }
  saveConfigToStorage();
  syncFormValues();
  sendToAhk("SET_SETTING", { key: path, value: defVal });
}

function resetActiveTab() {
  if (!confirm(t("confirmResetTab"))) return;

  if (activeTabId === "tab-general") {
    currentConfig.general = JSON.parse(JSON.stringify(window.DEFAULT_CONFIG.general));
    saveConfigToStorage();
    syncFormValues();
    sendToAhk("SET_SETTING", { key: "general", value: currentConfig.general });
  } else if (activeTabId === "tab-appearance") {
    currentConfig.appearance = JSON.parse(JSON.stringify(window.DEFAULT_CONFIG.appearance));
    saveConfigToStorage();
    syncFormValues();
    sendToAhk("SET_SETTING", { key: "appearance", value: currentConfig.appearance });
  } else if (activeTabId === "tab-hotkeys") {
    const activeProf = currentConfig.hotkeys.activeProfile || "default";
    const defProf = window.DEFAULT_CONFIG.hotkeys.profiles["default"];
    currentConfig.hotkeys.profiles[activeProf] = JSON.parse(JSON.stringify(defProf));
    saveConfigToStorage();
    renderHotkeysList();
    sendToAhk("SET_SETTING", { key: `hotkeys.profiles.${activeProf}`, value: currentConfig.hotkeys.profiles[activeProf] });
  }
}

function updateResetButtonsStatus() {
  document.querySelectorAll(".btn-reset").forEach(btn => {
    const onclickAttr = btn.getAttribute("onclick");
    if (!onclickAttr) return;
    const match = onclickAttr.match(/resetField\('([^']+)'\)/);
    if (!match) return;
    const path = match[1];
    const currVal = getPropertyByPath(currentConfig, path);
    const defVal = getPropertyByPath(window.DEFAULT_CONFIG, path);
    const isModified = JSON.stringify(currVal) !== JSON.stringify(defVal);
    btn.classList.toggle("is-modified", isModified);
  });
}

function getActiveProfileName() {
  return currentConfig.hotkeys.activeProfile || "default";
}

function getActiveProfileBinds() {
  const profName = getActiveProfileName();
  if (!currentConfig.hotkeys.profiles[profName]) {
    currentConfig.hotkeys.profiles[profName] = {};
  }
  return currentConfig.hotkeys.profiles[profName];
}

function syncProfileSelect() {
  const sel = document.getElementById("profile-select");
  if (!sel) return;
  sel.innerHTML = "";
  const profiles = Object.keys(currentConfig.hotkeys.profiles);
  const active = getActiveProfileName();
  profiles.forEach(name => {
    const opt = document.createElement("option");
    opt.value = name;
    opt.textContent = name === "default" ? (currentLang === "ru" ? "По умолчанию" : "Default") : name;
    if (name === active) opt.selected = true;
    sel.appendChild(opt);
  });
}

function onProfileChange(profName) {
  currentConfig.hotkeys.activeProfile = profName;
  saveConfigToStorage();
  renderHotkeysList();
  sendToAhk("SWITCH_KEYBIND_PROFILE", { profile: profName });
}

function addNewProfile() {
  const name = prompt(t("promptNewProfile"));
  if (!name || !name.trim()) return;
  const cleanName = name.trim();
  if (currentConfig.hotkeys.profiles[cleanName]) {
    alert("Profile already exists.");
    return;
  }
  const defBinds = window.DEFAULT_CONFIG.hotkeys.profiles["default"] || {};
  const initialBinds = JSON.parse(JSON.stringify(defBinds));
  currentConfig.hotkeys.profiles[cleanName] = initialBinds;
  currentConfig.hotkeys.activeProfile = cleanName;
  saveConfigToStorage();
  syncProfileSelect();
  renderHotkeysList();
  sendToAhk("SAVE_KEYBIND_PROFILE", { profile: cleanName, binds: initialBinds });
}

function renameProfile() {
  const active = getActiveProfileName();
  if (active === "default") {
    alert(t("cannotDeleteDefaultProfile"));
    return;
  }
  const newName = prompt(t("promptRenameProfile"), active);
  if (!newName || !newName.trim() || newName.trim() === active) return;
  const clean = newName.trim();
  if (currentConfig.hotkeys.profiles[clean]) {
    alert("Profile already exists.");
    return;
  }
  const binds = currentConfig.hotkeys.profiles[active];
  delete currentConfig.hotkeys.profiles[active];
  currentConfig.hotkeys.profiles[clean] = binds;
  currentConfig.hotkeys.activeProfile = clean;
  saveConfigToStorage();
  syncProfileSelect();
  renderHotkeysList();
  sendToAhk("RENAME_KEYBIND_PROFILE", { oldName: active, newName: clean });
}

function duplicateProfile() {
  const active = getActiveProfileName();
  const defName = active + t("duplicateProfileSuffix");
  const newName = prompt(t("promptDuplicateProfile"), defName);
  if (!newName || !newName.trim()) return;
  const clean = newName.trim();
  if (currentConfig.hotkeys.profiles[clean]) {
    alert("Profile already exists.");
    return;
  }
  const bindsCopy = JSON.parse(JSON.stringify(currentConfig.hotkeys.profiles[active] || {}));
  currentConfig.hotkeys.profiles[clean] = bindsCopy;
  currentConfig.hotkeys.activeProfile = clean;
  saveConfigToStorage();
  syncProfileSelect();
  renderHotkeysList();
  sendToAhk("SAVE_KEYBIND_PROFILE", { profile: clean, binds: bindsCopy });
}

function deleteProfile() {
  const active = getActiveProfileName();
  if (active === "default") {
    alert(t("cannotDeleteDefaultProfile"));
    return;
  }
  if (!confirm(t("confirmDeleteProfile", { name: active }))) return;
  delete currentConfig.hotkeys.profiles[active];
  currentConfig.hotkeys.activeProfile = "default";
  saveConfigToStorage();
  syncProfileSelect();
  renderHotkeysList();
  sendToAhk("DELETE_KEYBIND_PROFILE", { profile: active });
}

function filterHotkeys(query) {
  currentSearchQuery = (query || "").trim().toLowerCase();
  renderHotkeysList();
}

function renderHotkeysList() {
  const container = document.getElementById("hotkeys-list-container");
  if (!container) return;

  const binds = getActiveProfileBinds();
  const defBinds = window.DEFAULT_CONFIG.hotkeys.profiles["default"] || {};

  const groups = {
    sys: { title: currentLang === "ru" ? "Системные команды" : "System Commands", items: [] },
    overview: { title: currentLang === "ru" ? "Обзор и навигация" : "Overview & Navigation", items: [] },
    pocket: { title: currentLang === "ru" ? "Карман" : "Pocket", items: [] },
    workspaces: { title: currentLang === "ru" ? "Рабочие столы" : "Workspaces", items: [] },
    window: { title: currentLang === "ru" ? "Оконные операции" : "Window Actions", items: [] }
  };

  HOTKEY_ACTIONS.forEach(act => {
    const title = t(act.i18nTitle, act.param ? { n: act.param } : null);
    const desc = t(act.i18nDesc, act.param ? { n: act.param } : null);
    const assignedBinds = binds[act.key] || [];

    if (currentSearchQuery) {
      const matchTitle = title.toLowerCase().includes(currentSearchQuery);
      const matchDesc = desc.toLowerCase().includes(currentSearchQuery);
      const matchBinds = assignedBinds.some(b => b.toLowerCase().includes(currentSearchQuery));
      if (!matchTitle && !matchDesc && !matchBinds) return;
    }

    groups[act.group].items.push({
      action: act,
      title: title,
      desc: desc,
      assigned: assignedBinds,
      defaults: defBinds[act.key] || []
    });
  });

  let html = "";
  for (const gKey in groups) {
    const group = groups[gKey];
    if (group.items.length === 0) continue;

    html += `<div class="settings-group">
      <div class="group-title">${group.title}</div>
      <div class="group-cards">`;

    group.items.forEach(item => {
      const isModified = JSON.stringify(item.assigned) !== JSON.stringify(item.defaults);
      const isRecording = recordingTarget && recordingTarget.actionKey === item.action.key;

      html += `<div class="keybind-row" data-action="${item.action.key}">
        <div class="setting-info">
          <div class="setting-title">${item.title}</div>
          ${item.desc ? `<div class="setting-desc">${item.desc}</div>` : ''}
        </div>
        <div class="setting-control-group">
          <div class="chips-container" id="chips-${item.action.key}">`;

      if (item.assigned.length === 0 && !isRecording) {
        html += `<span class="empty-bind-placeholder">${t("noKeybinds")}</span>`;
      } else {
        item.assigned.forEach((bindStr, idx) => {
          html += `<div class="key-chip">
            <kbd>${escapeHtml(bindStr)}</kbd>
            <span class="chip-remove" onclick="removeKeybind('${item.action.key}', ${idx})" title="${currentLang === 'ru' ? 'Удалить' : 'Remove'}">
              <svg viewBox="0 0 24 24"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>
            </span>
          </div>`;
        });
      }

      if (isRecording) {
        html += `<div class="recording-chip">
          <span>${t("pressKeyPrompt")}</span>
          <span class="recording-cancel" onclick="cancelRecording()">${t("cancelKeyRecord")}</span>
        </div>`;
      } else {
        html += `<button class="btn-add-bind" onclick="startRecording('${item.action.key}')">${t("addKeybindBtn")}</button>`;
      }

      html += `</div>
          <button class="btn-reset ${isModified ? 'is-modified' : ''}" onclick="resetKeybindAction('${item.action.key}')" title="${t('resetFieldTooltip')}">
            <svg viewBox="0 0 24 24"><path d="M17.65 6.35C16.2 4.9 14.21 4 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08c-.82 2.33-3.04 4-5.65 4-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z"/></svg>
          </button>
        </div>
      </div>`;
    });

    html += `</div></div>`;
  }

  container.innerHTML = html;
}

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}

function removeKeybind(actionKey, index) {
  const binds = getActiveProfileBinds();
  if (binds[actionKey]) {
    binds[actionKey].splice(index, 1);
    saveConfigToStorage();
    renderHotkeysList();
    sendToAhk("SET_SETTING", { key: `hotkeys.profiles.${getActiveProfileName()}.${actionKey}`, value: binds[actionKey] });
  }
}

function resetKeybindAction(actionKey) {
  const defBinds = window.DEFAULT_CONFIG.hotkeys.profiles["default"] || {};
  const binds = getActiveProfileBinds();
  binds[actionKey] = JSON.parse(JSON.stringify(defBinds[actionKey] || []));
  saveConfigToStorage();
  renderHotkeysList();
  sendToAhk("SET_SETTING", { key: `hotkeys.profiles.${getActiveProfileName()}.${actionKey}`, value: binds[actionKey] });
}

function startRecording(actionKey) {
  isNumLockHeld = false;
  recordingTarget = { actionKey: actionKey };
  renderHotkeysList();
  sendToAhk("START_KEY_RECORDING", {});
}

function cancelRecording() {
  isNumLockHeld = false;
  recordingTarget = null;
  renderHotkeysList();
  sendToAhk("STOP_KEY_RECORDING", {});
}

function commitRecordedKey(shortcutString) {
  if (!recordingTarget) return;
  const actionKey = recordingTarget.actionKey;
  const binds = getActiveProfileBinds();

  if (!binds[actionKey]) binds[actionKey] = [];
  if (!binds[actionKey].includes(shortcutString)) {
    binds[actionKey].push(shortcutString);
  }

  recordingTarget = null;
  isNumLockHeld = false;
  saveConfigToStorage();
  renderHotkeysList();
  sendToAhk("SET_SETTING", { key: `hotkeys.profiles.${getActiveProfileName()}.${actionKey}`, value: binds[actionKey] });
  sendToAhk("STOP_KEY_RECORDING", {});
}

window.addEventListener("keyup", (e) => {
  if (e.key === "NumLock" || e.code === "NumLock") {
    isNumLockHeld = false;
  }
});

window.addEventListener("mousedown", (e) => {
  if (!recordingTarget) return;

  if (e.target && e.target.classList.contains("recording-cancel")) {
    return;
  }

  e.preventDefault();
  e.stopPropagation();

  if (recordingTarget.actionKey === "window_mouse_modifier") {
    return;
  }

  let btnName = "";
  if (e.button === 0) btnName = "LButton";
  else if (e.button === 1) btnName = "MButton";
  else if (e.button === 2) btnName = "RButton";
  else if (e.button === 3) btnName = "XButton1";
  else if (e.button === 4) btnName = "XButton2";

  if (!btnName) return;

  const parts = [];
  if (isNumLockHeld) parts.push("NumLock");
  if (e.ctrlKey) parts.push("Ctrl");
  if (e.altKey) parts.push("Alt");
  if (e.shiftKey) parts.push("Shift");
  if (e.metaKey) parts.push("Win");

  parts.push(btnName);
  commitRecordedKey(parts.join(" + "));
});

window.addEventListener("wheel", (e) => {
  if (!recordingTarget) return;

  e.preventDefault();
  e.stopPropagation();

  if (recordingTarget.actionKey === "window_mouse_modifier") {
    return;
  }

  const wheelName = e.deltaY < 0 ? "WheelUp" : "WheelDown";
  const parts = [];
  if (isNumLockHeld) parts.push("NumLock");
  if (e.ctrlKey) parts.push("Ctrl");
  if (e.altKey) parts.push("Alt");
  if (e.shiftKey) parts.push("Shift");
  if (e.metaKey) parts.push("Win");

  parts.push(wheelName);
  commitRecordedKey(parts.join(" + "));
}, { passive: false });

window.addEventListener("keydown", (e) => {
  if (!recordingTarget) return;

  e.preventDefault();
  e.stopPropagation();

  if (e.key === "Escape" && !e.ctrlKey && !e.altKey && !e.shiftKey && !e.metaKey && !isNumLockHeld) {
    cancelRecording();
    return;
  }

  if (recordingTarget.actionKey === "window_mouse_modifier") {
    let modName = "";
    if (e.key === "NumLock" || e.code === "NumLock") modName = "NumLock";
    else if (e.key === "Control" || e.key === "Ctrl") modName = "Ctrl";
    else if (e.key === "Alt") modName = "Alt";
    else if (e.key === "Shift") modName = "Shift";
    else if (e.key === "Meta") modName = "Win";

    if (modName) {
      const parts = [];
      if (isNumLockHeld && modName !== "NumLock") parts.push("NumLock");
      if (e.ctrlKey && modName !== "Ctrl") parts.push("Ctrl");
      if (e.altKey && modName !== "Alt") parts.push("Alt");
      if (e.shiftKey && modName !== "Shift") parts.push("Shift");
      if (e.metaKey && modName !== "Win") parts.push("Win");
      parts.push(modName);
      commitRecordedKey(parts.join(" + "));
      return;
    }
  }

  if (e.key === "NumLock" || e.code === "NumLock") {
    isNumLockHeld = true;
    return;
  }

  if (["Control", "Alt", "Shift", "Meta"].includes(e.key)) {
    return;
  }

  const parts = [];
  if (isNumLockHeld) parts.push("NumLock");
  if (e.ctrlKey) parts.push("Ctrl");
  if (e.altKey) parts.push("Alt");
  if (e.shiftKey) parts.push("Shift");
  if (e.metaKey) parts.push("Win");

  let keyName = e.code || e.key;
  if (keyName.startsWith("Key")) keyName = keyName.substring(3);
  else if (keyName.startsWith("Digit")) keyName = keyName.substring(5);
  else if (keyName.startsWith("Numpad")) {
    const numSub = keyName.substring(6);
    if (numSub.length > 0 && !isNaN(numSub)) {
      keyName = numSub;
    }
  }
  else if (keyName === "Space") keyName = "Space";
  else if (keyName === "Tab") keyName = "Tab";
  else if (keyName === "Enter") keyName = "Enter";

  parts.push(keyName);
  commitRecordedKey(parts.join(" + "));
});

if (window.chrome && window.chrome.webview) {
  window.chrome.webview.addEventListener("message", (event) => {
    let msg = event.data;
    if (typeof msg === "string") {
      try { msg = JSON.parse(msg); } catch (e) {}
    }
    if (msg && msg.action === "LOAD_CONFIG" && msg.config) {
      currentConfig = Object.assign({}, window.DEFAULT_CONFIG, msg.config);
      if (currentConfig.language) {
        currentLang = currentConfig.language;
      }
      saveConfigToStorage();
      setLanguage(currentLang);
      syncFormValues();
    }
  });
}

document.addEventListener("DOMContentLoaded", () => {
  setLanguage(currentConfig.language || "en");
  syncFormValues();
  sendToAhk("SETTINGS_READY", {});
});
