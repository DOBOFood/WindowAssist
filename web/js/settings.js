// Theme follows the Windows app theme and accent color, sent by AHK.
function hexToRgb(hex) {
  return {
    r: parseInt(hex.slice(1, 3), 16),
    g: parseInt(hex.slice(3, 5), 16),
    b: parseInt(hex.slice(5, 7), 16)
  };
}

function mixColor(hex, target, amount) {
  const a = hexToRgb(hex);
  const b = hexToRgb(target);
  const mix = (x, y) => Math.round(x + (y - x) * amount);
  return "#" + [mix(a.r, b.r), mix(a.g, b.g), mix(a.b, b.b)]
    .map(v => v.toString(16).padStart(2, "0"))
    .join("");
}

let lastSystemTheme = { dark: false, accent: "#0078D7", os: "win11" };

function applyTheme(info) {
  if (info && typeof info === "object") {
    lastSystemTheme = Object.assign({}, lastSystemTheme, info);
  }
  const src = lastSystemTheme;
  const root = document.documentElement;
  const themePref = (typeof currentConfig === "object" && currentConfig)
    ? (getPropertyByPath(currentConfig, "appearance.settingsTheme") || "auto")
    : "auto";
  const dark = themePref === "dark" ? true : (themePref === "light" ? false : !!src.dark);
  const accent = /^#[0-9a-fA-F]{6}$/.test(src.accent || "") ? src.accent : "#0078D7";
  const rgb = hexToRgb(accent);

  root.setAttribute("data-theme", dark ? "dark" : "light");
  root.setAttribute("data-os", src.os === "win11" ? "win11" : "win10");
  root.style.colorScheme = dark ? "dark" : "light";
  root.style.setProperty("--accent", accent);
  root.style.setProperty("--accent-hover", mixColor(accent, dark ? "#ffffff" : "#000000", dark ? 0.12 : 0.08));
  root.style.setProperty("--accent-pressed", mixColor(accent, dark ? "#ffffff" : "#000000", dark ? 0.22 : 0.18));
  root.style.setProperty("--accent-subtle", `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${dark ? 0.2 : 0.12})`);
  root.style.setProperty("--accent-faint", `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${dark ? 0.3 : 0.2})`);
}

function onSettingsThemeChange(val) {
  updateSetting("appearance.settingsTheme", val);
  applyTheme(lastSystemTheme);
}

// State Management
// Nested objects from the cache must not hide new default keys (a shallow
// assign dropped fields added in later versions).
function deepMerge(base, override) {
  if (!override || typeof override !== "object" || Array.isArray(override)) return base;
  const result = Object.assign({}, base);
  for (const key in override) {
    const baseValue = result[key];
    const overrideValue = override[key];
    if (baseValue && overrideValue
        && typeof baseValue === "object" && typeof overrideValue === "object"
        && !Array.isArray(baseValue) && !Array.isArray(overrideValue)) {
      result[key] = deepMerge(baseValue, overrideValue);
    } else {
      result[key] = overrideValue;
    }
  }
  return result;
}

function loadCachedConfig() {
  try {
    const cached = localStorage.getItem("windowassist_config");
    if (cached) {
      const parsed = JSON.parse(cached);
      // Drop the cache when the config schema changed, migrations run in AHK.
      if (parsed && typeof parsed === "object"
          && parsed.configVersion === window.DEFAULT_CONFIG.configVersion) {
        return deepMerge(window.DEFAULT_CONFIG, parsed);
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
let heldCustomModifier = ""; // Tracks NumLock or custom primary modifier during recording

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
  { key: "window_move_left", group: "window", i18nTitle: "act_window_move_left", i18nDesc: "act_window_move_left_desc" },
  { key: "window_move_right", group: "window", i18nTitle: "act_window_move_right", i18nDesc: "act_window_move_right_desc" },
  { key: "window_move_up", group: "window", i18nTitle: "act_window_move_up", i18nDesc: "act_window_move_up_desc" },
  { key: "window_move_down", group: "window", i18nTitle: "act_window_move_down", i18nDesc: "act_window_move_down_desc" },
  { key: "window_resize_wider", group: "window", i18nTitle: "act_window_resize_wider", i18nDesc: "act_window_resize_wider_desc" },
  { key: "window_resize_narrower", group: "window", i18nTitle: "act_window_resize_narrower", i18nDesc: "act_window_resize_narrower_desc" },
  { key: "window_resize_taller", group: "window", i18nTitle: "act_window_resize_taller", i18nDesc: "act_window_resize_taller_desc" },
  { key: "window_resize_shorter", group: "window", i18nTitle: "act_window_resize_shorter", i18nDesc: "act_window_resize_shorter_desc" },
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
  if (action !== "SETTINGS_READY" && action !== "START_KEY_RECORDING" && action !== "STOP_KEY_RECORDING" && action !== "PREVIEW_OSD") {
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

function renderLanguageOptions() {
  const popup = document.getElementById("lang-popup");
  if (!popup) return;

  const languages = window.LANGUAGES || [];
  const dictionaries = window.I18N || {};
  popup.innerHTML = "";

  languages.forEach(language => {
    if (!dictionaries[language.code]) return;

    const option = document.createElement("div");
    option.className = "lang-option";
    option.setAttribute("data-lang", language.code);

    const name = document.createElement("span");
    name.className = "lang-name";
    name.textContent = language.name;

    const tag = document.createElement("span");
    tag.className = "lang-code-tag";
    tag.textContent = language.tag;

    option.appendChild(name);
    option.appendChild(tag);
    option.addEventListener("click", (event) => selectLanguage(language.code, event));
    popup.appendChild(option);
  });

  setLanguage(currentLang);
}

function setLanguage(lang) {
  const dictionaries = window.I18N || {};
  if (!dictionaries[lang]) lang = "en";

  currentLang = lang;
  currentConfig.language = lang;
  saveConfigToStorage();

  const meta = (window.LANGUAGES || []).find(language => language.code === lang);
  const currentLabel = document.getElementById("lang-current-label");
  if (currentLabel) currentLabel.textContent = meta ? meta.tag : lang.toUpperCase();

  document.documentElement.lang = lang;
  document.querySelectorAll(".lang-option").forEach(option => {
    option.classList.toggle("active", option.getAttribute("data-lang") === lang);
  });

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
  renderPrimaryModifierBar();
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

  const elSafeZone = document.getElementById("gen_wm_safeZone");
  if (elSafeZone) {
    const safeZone = getPropertyByPath(currentConfig, "general.windowMover.safeZone");
    const defaultSafeZone = getPropertyByPath(window.DEFAULT_CONFIG, "general.windowMover.safeZone");
    elSafeZone.value = (safeZone !== undefined) ? safeZone : (defaultSafeZone !== undefined ? defaultSafeZone : 8);
  }

  const elKeyboardStep = document.getElementById("gen_wm_keyboardStep");
  if (elKeyboardStep) {
    const step = getPropertyByPath(currentConfig, "general.windowMover.keyboardStep");
    const defaultStep = getPropertyByPath(window.DEFAULT_CONFIG, "general.windowMover.keyboardStep");
    elKeyboardStep.value = (step !== undefined) ? step : (defaultStep !== undefined ? defaultStep : 20);
  }

  const elSnapEnabled = document.getElementById("gen_wm_snapEnabled");
  if (elSnapEnabled) {
    const snapVal = getPropertyByPath(currentConfig, "general.windowMover.snapEnabled");
    elSnapEnabled.checked = (snapVal === undefined) ? true : !!snapVal;
  }

  const elAutostart = document.getElementById("gen_autostart");
  if (elAutostart) elAutostart.checked = !!getPropertyByPath(currentConfig, "general.autostart.enabled");

  const elTbAuto = document.getElementById("gen_tb_autoHide");
  if (elTbAuto) elTbAuto.checked = !!currentConfig.general.titleBar.autoHide;
  const elTbDark = document.getElementById("gen_tb_darkTheme");
  if (elTbDark) elTbDark.checked = !!currentConfig.general.titleBar.darkTheme;

  document.getElementById("gen_tb_hideTaskList").checked = !!currentConfig.general.taskbar.hideTaskList;

  const elSettingsTheme = document.getElementById("app_settingsTheme");
  if (elSettingsTheme) {
    const themeVal = getPropertyByPath(currentConfig, "appearance.settingsTheme");
    elSettingsTheme.value = (themeVal === "light" || themeVal === "dark" || themeVal === "auto") ? themeVal : "auto";
  }

  const elOvDesign = document.getElementById("app_overview_design");
  if (elOvDesign) {
    const ovDesign = getPropertyByPath(currentConfig, "appearance.overview.design") || "default";
    elOvDesign.value = ovDesign;
  }
  const elOvRadius = document.getElementById("app_overview_cornerRadius");
  if (elOvRadius) {
    const ovRad = getPropertyByPath(currentConfig, "appearance.overview.cornerRadius");
    elOvRadius.value = (ovRad !== undefined) ? ovRad : 12;
  }
  syncColorControl("appearance.overview.backgroundColor", "col_overview_bgColor", "text_overview_bgColor", "box_overview_bgColor");
  const elOvBgOpacity = document.getElementById("app_overview_bgOpacity");
  if (elOvBgOpacity) {
    const ovOp = getPropertyByPath(currentConfig, "appearance.overview.backgroundOpacity");
    elOvBgOpacity.value = (ovOp !== undefined) ? ovOp : 50;
  }

  const elAnimEnabled = document.getElementById("app_animationsEnabled");
  if (elAnimEnabled) {
    const enabled = getPropertyByPath(currentConfig, "appearance.animationsEnabled");
    elAnimEnabled.checked = (enabled === undefined) ? true : !!enabled;
  }
  updateAnimationDurationControlState();

  document.getElementById("app_animationDurationMs").value = currentConfig.appearance.animationDurationMs;

  syncColorControl("appearance.colors.workspaceBorderHover", "col_workspaceBorderHover", "text_col_wsBorder", "box_col_wsBorder");
  syncColorControl("appearance.colors.pocketTheme", "col_pocketTheme", "text_col_pocket", "box_col_pocket");
  syncColorControl("appearance.colors.windowDragPulse", "col_windowDragPulse", "text_col_dragPulse", "box_col_dragPulse");
  const elDragPulseWidth = document.getElementById("app_windowDragPulseWidth");
  if (elDragPulseWidth) elDragPulseWidth.value = currentConfig.appearance.colors.windowDragPulseWidth || 3;
  syncColorControl("appearance.colors.pocketWindowBorder", "col_pocketWindowBorder", "text_col_pocketBorder", "box_col_pocketBorder");
  document.getElementById("app_pocketBorderWidth").value = currentConfig.appearance.colors.pocketBorderWidth;
  syncColorControl("appearance.colors.snapPreview", "col_snapPreview", "text_col_snapPreview", "box_col_snapPreview");

  syncColorControl("appearance.osd.backgroundColor", "col_osd_bgColor", "text_osd_bgColor", "box_osd_bgColor");
  const elOsdBgOpacity = document.getElementById("app_osd_bgOpacity");
  if (elOsdBgOpacity) {
    const op = getPropertyByPath(currentConfig, "appearance.osd.backgroundOpacity");
    elOsdBgOpacity.value = (op !== undefined) ? op : 100;
  }
  syncColorControl("appearance.osd.textColor", "col_osd_textColor", "text_osd_textColor", "box_osd_textColor");
  const elOsdBorderTrans = document.getElementById("app_osd_borderTransparent");
  if (elOsdBorderTrans) elOsdBorderTrans.checked = !!getPropertyByPath(currentConfig, "appearance.osd.borderTransparent");
  syncColorControl("appearance.osd.borderColor", "col_osd_borderColor", "text_osd_borderColor", "box_osd_borderColor");
  const elOsdBorderWidth = document.getElementById("app_osd_borderWidth");
  if (elOsdBorderWidth) {
    const bw = getPropertyByPath(currentConfig, "appearance.osd.borderWidth");
    elOsdBorderWidth.value = (bw !== undefined) ? bw : 1;
  }
  const elOsdCornerRadius = document.getElementById("app_osd_cornerRadius");
  if (elOsdCornerRadius) {
    const cr = getPropertyByPath(currentConfig, "appearance.osd.cornerRadius");
    elOsdCornerRadius.value = (cr !== undefined) ? cr : 10;
  }
  updateOsdBorderControlsState();
  updateOsdPreview();

  syncProfileSelect();
  renderPrimaryModifierBar();
  renderHotkeysList();
  updateResetButtonsStatus();
}

function onAnimationsEnabledChange(checked) {
  updateSetting("appearance.animationsEnabled", checked ? 1 : 0);
  updateAnimationDurationControlState();
}

function updateAnimationDurationControlState() {
  const raw = getPropertyByPath(currentConfig, "appearance.animationsEnabled");
  const enabled = (raw === undefined) ? true : !!raw;
  const rowDur = document.getElementById("row_animationDurationMs");
  if (rowDur) rowDur.classList.toggle("is-disabled", !enabled);
}

function onClampedNumberChange(configPath, rawVal, minVal, maxVal, fallback) {
  let num = parseInt(rawVal, 10);
  if (isNaN(num)) num = fallback;
  num = Math.min(maxVal, Math.max(minVal, num));
  setPropertyByPath(currentConfig, configPath, num);
  saveConfigToStorage();
  syncFormValues();
  sendToAhk("SET_SETTING", { key: configPath, value: num });
}

function onOsdColorLive(configPath, hex) {
  setPropertyByPath(currentConfig, configPath, hex);
  if (configPath === "appearance.osd.backgroundColor") {
    syncColorControl(configPath, "col_osd_bgColor", "text_osd_bgColor", "box_osd_bgColor");
  } else if (configPath === "appearance.osd.textColor") {
    syncColorControl(configPath, "col_osd_textColor", "text_osd_textColor", "box_osd_textColor");
  } else if (configPath === "appearance.osd.borderColor") {
    syncColorControl(configPath, "col_osd_borderColor", "text_osd_borderColor", "box_osd_borderColor");
  }
  updateOsdPreview();
}

function onOsdNumberChange(configPath, rawVal, minVal, maxVal, fallback) {
  let num = parseInt(rawVal, 10);
  if (isNaN(num)) num = fallback;
  num = Math.min(maxVal, Math.max(minVal, num));
  setPropertyByPath(currentConfig, configPath, num);
  saveConfigToStorage();
  syncFormValues();
  sendToAhk("SET_SETTING", { key: configPath, value: num });
}

function onOsdBorderTransparentChange(checked) {
  updateSetting("appearance.osd.borderTransparent", !!checked);
  updateOsdBorderControlsState();
  updateOsdPreview();
}

function updateOsdBorderControlsState() {
  const isTransparent = !!getPropertyByPath(currentConfig, "appearance.osd.borderTransparent");
  const rowColor = document.getElementById("row_osd_borderColor");
  const rowWidth = document.getElementById("row_osd_borderWidth");
  if (rowColor) rowColor.classList.toggle("is-disabled", isTransparent);
  if (rowWidth) rowWidth.classList.toggle("is-disabled", isTransparent);
}

function updateOsdPreview() {
  const strip = document.getElementById("osd-preview-strip");
  if (!strip) return;

  const bgHex = getPropertyByPath(currentConfig, "appearance.osd.backgroundColor") || "#1A1A1A";
  const bgOpacityRaw = getPropertyByPath(currentConfig, "appearance.osd.backgroundOpacity");
  const bgOpacity = Math.min(100, Math.max(0, bgOpacityRaw !== undefined ? Number(bgOpacityRaw) : 100));
  const textHex = getPropertyByPath(currentConfig, "appearance.osd.textColor") || "#FFFFFF";
  const borderTransparent = !!getPropertyByPath(currentConfig, "appearance.osd.borderTransparent");
  const borderHex = getPropertyByPath(currentConfig, "appearance.osd.borderColor") || "#3D3D3D";
  const borderWidthRaw = getPropertyByPath(currentConfig, "appearance.osd.borderWidth");
  const borderWidth = Math.min(10, Math.max(1, borderWidthRaw !== undefined ? Number(borderWidthRaw) : 1));
  const cornerRadiusRaw = getPropertyByPath(currentConfig, "appearance.osd.cornerRadius");
  const cornerRadius = Math.min(32, Math.max(0, cornerRadiusRaw !== undefined ? Number(cornerRadiusRaw) : 10));

  const rgb = /^#[0-9a-fA-F]{6}$/.test(bgHex) ? hexToRgb(bgHex) : { r: 26, g: 26, b: 26 };
  const bgCss = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${(bgOpacity / 100).toFixed(2)})`;

  strip.querySelectorAll(".osd-preview-pill").forEach(pill => {
    pill.style.backgroundColor = bgCss;
    pill.style.color = textHex;
    pill.style.borderRadius = `${cornerRadius}px`;
    pill.style.borderStyle = "solid";
    if (borderTransparent) {
      pill.style.borderWidth = "0px";
      pill.style.borderColor = "transparent";
    } else {
      pill.style.borderWidth = `${borderWidth}px`;
      pill.style.borderColor = borderHex;
    }
  });
}

function previewOsd(kind) {
  sendToAhk("PREVIEW_OSD", { kind: kind });
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

function exportSettings() {
  sendToAhk("EXPORT_SETTINGS", { title: t("settingsExport") });
}

function importSettings() {
  sendToAhk("IMPORT_SETTINGS", { title: t("settingsImport") });
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
  if (path === "appearance.settingsTheme") {
    applyTheme(lastSystemTheme);
  }
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
    applyTheme(lastSystemTheme);
    syncFormValues();
    sendToAhk("SET_SETTING", { key: "appearance", value: currentConfig.appearance });
  } else if (activeTabId === "tab-hotkeys") {
    const activeProf = currentConfig.hotkeys.activeProfile || "default";
    const defProf = window.DEFAULT_CONFIG.hotkeys.profiles["default"];
    currentConfig.hotkeys.profiles[activeProf] = JSON.parse(JSON.stringify(defProf));
    setPrimaryModifierValue(activeProf, "NumLock");
    saveConfigToStorage();
    renderPrimaryModifierBar();
    renderHotkeysList();
    sendToAhk("APPLY_PRIMARY_MODIFIER", {
      profile: activeProf,
      primaryModifier: "NumLock",
      binds: currentConfig.hotkeys.profiles[activeProf]
    });
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
    opt.textContent = name === "default" ? t("defaultProfileName") : name;
    if (name === active) opt.selected = true;
    sel.appendChild(opt);
  });
}

function getPrimaryModifier(profName) {
  const active = profName || getActiveProfileName();
  const map = currentConfig.hotkeys && currentConfig.hotkeys.primaryModifiers;
  return (map && map[active]) ? map[active] : "NumLock";
}

function setPrimaryModifierValue(profName, mod) {
  if (!currentConfig.hotkeys.primaryModifiers || typeof currentConfig.hotkeys.primaryModifiers !== "object") {
    currentConfig.hotkeys.primaryModifiers = {};
  }
  currentConfig.hotkeys.primaryModifiers[profName] = mod;
}

function normalizeModToken(token) {
  const low = (token || "").trim().toLowerCase();
  if (low === "control") return "ctrl";
  if (low === "windows") return "win";
  return low;
}

function replacePrimaryModifierInCombo(combo, oldMod, newMod, isPrefixAction) {
  if (typeof combo !== "string" || !combo.trim()) return combo;
  const parts = combo.split("+").map(p => p.trim()).filter(Boolean);
  if (!parts.length) return combo;

  const oldNorm = normalizeModToken(oldMod);
  const newNorm = normalizeModToken(newMod);

  if (isPrefixAction) {
    let found = false;
    const replaced = [];
    for (const p of parts) {
      if (normalizeModToken(p) === oldNorm) {
        found = true;
        if (!replaced.some(r => normalizeModToken(r) === newNorm)) {
          replaced.push(newMod);
        }
      } else {
        if (!replaced.some(r => normalizeModToken(r) === normalizeModToken(p))) {
          replaced.push(p);
        }
      }
    }
    return found ? replaced.join(" + ") : combo;
  }

  if (parts.length < 2) return combo;
  const mods = parts.slice(0, -1);
  const key = parts[parts.length - 1];
  let found = false;
  const newMods = [];

  for (const m of mods) {
    if (normalizeModToken(m) === oldNorm) {
      found = true;
      if (!newMods.some(r => normalizeModToken(r) === newNorm)) {
        newMods.push(newMod);
      }
    } else {
      if (!newMods.some(r => normalizeModToken(r) === normalizeModToken(m))) {
        newMods.push(m);
      }
    }
  }

  if (!found) return combo;
  if (normalizeModToken(key) === newNorm) return combo;
  return [...newMods, key].join(" + ");
}

function applyPrimaryModifier(newMod) {
  const cleanMod = (newMod || "").trim();
  if (!cleanMod) return;
  const activeProf = getActiveProfileName();
  const oldMod = getPrimaryModifier(activeProf);
  const binds = getActiveProfileBinds();

  if (normalizeModToken(cleanMod) !== normalizeModToken(oldMod)) {
    for (const actionKey in binds) {
      const list = binds[actionKey];
      if (!Array.isArray(list)) continue;
      const isPrefix = (actionKey === "window_mouse_modifier" || actionKey === "move_window_prefix");
      const updated = [];
      for (const combo of list) {
        const nextCombo = replacePrimaryModifierInCombo(combo, oldMod, cleanMod, isPrefix);
        if (!updated.includes(nextCombo)) {
          updated.push(nextCombo);
        }
      }
      binds[actionKey] = updated;
    }
  }

  setPrimaryModifierValue(activeProf, cleanMod);
  recordingTarget = null;
  heldCustomModifier = "";
  saveConfigToStorage();
  renderPrimaryModifierBar();
  renderHotkeysList();
  sendToAhk("APPLY_PRIMARY_MODIFIER", {
    profile: activeProf,
    primaryModifier: cleanMod,
    binds: binds
  });
  sendToAhk("STOP_KEY_RECORDING", {});
}

function startPrimaryModifierRecording() {
  heldCustomModifier = "";
  recordingTarget = { actionKey: "__PRIMARY_MODIFIER__" };
  renderPrimaryModifierBar();
  renderHotkeysList();
  sendToAhk("START_KEY_RECORDING", {});
}

function resetPrimaryModifier() {
  applyPrimaryModifier("NumLock");
}

function renderPrimaryModifierBar() {
  const container = document.getElementById("primary-modifier-controls");
  if (!container) return;

  const currentMod = getPrimaryModifier();
  const isRecording = recordingTarget && recordingTarget.actionKey === "__PRIMARY_MODIFIER__";
  const isModified = normalizeModToken(currentMod) !== "numlock";

  if (isRecording) {
    container.innerHTML = `<div class="recording-chip">
      <span>${escapeHtml(t("pressKeyPrompt"))}</span>
      <span class="recording-cancel" onclick="cancelRecording()">${escapeHtml(t("cancelKeyRecord"))}</span>
    </div>`;
    return;
  }

  container.innerHTML = `
    <span class="primary-modifier-chip">${escapeHtml(currentMod)}</span>
    <button class="btn-add-bind" onclick="startPrimaryModifierRecording()">${escapeHtml(t("changePrimaryModBtn"))}</button>
    <button class="btn-reset ${isModified ? "is-modified" : ""}" onclick="resetPrimaryModifier()" title="${escapeHtml(t("resetFieldTooltip"))}">
      <svg viewBox="0 0 24 24"><path d="M17.65 6.35C16.2 4.9 14.21 4 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08c-.82 2.33-3.04 4-5.65 4-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z"/></svg>
    </button>
  `;
}

function onProfileChange(profName) {
  currentConfig.hotkeys.activeProfile = profName;
  saveConfigToStorage();
  renderPrimaryModifierBar();
  renderHotkeysList();
  sendToAhk("SWITCH_KEYBIND_PROFILE", { profile: profName });
}

function addNewProfile() {
  const name = prompt(t("promptNewProfile"));
  if (!name || !name.trim()) return;
  const cleanName = name.trim();
  if (currentConfig.hotkeys.profiles[cleanName]) {
    alert(t("profileAlreadyExists"));
    return;
  }
  const defBinds = window.DEFAULT_CONFIG.hotkeys.profiles["default"] || {};
  const initialBinds = JSON.parse(JSON.stringify(defBinds));
  currentConfig.hotkeys.profiles[cleanName] = initialBinds;
  setPrimaryModifierValue(cleanName, "NumLock");
  currentConfig.hotkeys.activeProfile = cleanName;
  saveConfigToStorage();
  syncProfileSelect();
  renderPrimaryModifierBar();
  renderHotkeysList();
  sendToAhk("SAVE_KEYBIND_PROFILE", { profile: cleanName, binds: initialBinds, primaryModifier: "NumLock" });
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
    alert(t("profileAlreadyExists"));
    return;
  }
  const binds = currentConfig.hotkeys.profiles[active];
  const pm = getPrimaryModifier(active);
  delete currentConfig.hotkeys.profiles[active];
  if (currentConfig.hotkeys.primaryModifiers) {
    delete currentConfig.hotkeys.primaryModifiers[active];
  }
  currentConfig.hotkeys.profiles[clean] = binds;
  setPrimaryModifierValue(clean, pm);
  currentConfig.hotkeys.activeProfile = clean;
  saveConfigToStorage();
  syncProfileSelect();
  renderPrimaryModifierBar();
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
    alert(t("profileAlreadyExists"));
    return;
  }
  const bindsCopy = JSON.parse(JSON.stringify(currentConfig.hotkeys.profiles[active] || {}));
  const pm = getPrimaryModifier(active);
  currentConfig.hotkeys.profiles[clean] = bindsCopy;
  setPrimaryModifierValue(clean, pm);
  currentConfig.hotkeys.activeProfile = clean;
  saveConfigToStorage();
  syncProfileSelect();
  renderPrimaryModifierBar();
  renderHotkeysList();
  sendToAhk("SAVE_KEYBIND_PROFILE", { profile: clean, binds: bindsCopy, primaryModifier: pm });
}

function deleteProfile() {
  const active = getActiveProfileName();
  if (active === "default") {
    alert(t("cannotDeleteDefaultProfile"));
    return;
  }
  if (!confirm(t("confirmDeleteProfile", { name: active }))) return;
  delete currentConfig.hotkeys.profiles[active];
  if (currentConfig.hotkeys.primaryModifiers) {
    delete currentConfig.hotkeys.primaryModifiers[active];
  }
  currentConfig.hotkeys.activeProfile = "default";
  saveConfigToStorage();
  syncProfileSelect();
  renderPrimaryModifierBar();
  renderHotkeysList();
  sendToAhk("DELETE_KEYBIND_PROFILE", { profile: active });
}

function filterHotkeys(query) {
  currentSearchQuery = (query || "").trim().toLowerCase();
  renderHotkeysList();
}

function normalizeCombo(combo) {
  return combo.split("+")
    .map(part => part.trim().toLowerCase())
    .map(part => part === "control" ? "ctrl" : (part === "windows" ? "win" : part))
    .sort()
    .join("+");
}

// Actions that share the exact same shortcut. Order and Ctrl/Control spellings
// are ignored, but different modifier sets are distinct bindings (NumLock+Left
// and NumLock+Alt+Left can coexist).
function findHotkeyConflicts(binds) {
  const byCombo = new Map();
  for (const actionKey in binds) {
    for (const combo of binds[actionKey] || []) {
      if (typeof combo !== "string" || !combo.trim()) continue;
      const normalized = normalizeCombo(combo);
      if (!byCombo.has(normalized)) byCombo.set(normalized, new Set());
      byCombo.get(normalized).add(actionKey);
    }
  }

  const conflicts = new Map();
  const combos = [];
  byCombo.forEach((actions, normalized) => {
    if (actions.size < 2) return;
    combos.push(normalized);
    actions.forEach(actionKey => {
      if (!conflicts.has(actionKey)) conflicts.set(actionKey, new Set());
      actions.forEach(other => {
        if (other !== actionKey) conflicts.get(actionKey).add(other);
      });
    });
  });
  return { conflicts, combos };
}

function renderHotkeysList() {
  const container = document.getElementById("hotkeys-list-container");
  if (!container) return;

  const binds = getActiveProfileBinds();
  const defBinds = window.DEFAULT_CONFIG.hotkeys.profiles["default"] || {};
  const { conflicts, combos } = findHotkeyConflicts(binds);

  const groups = {
    sys: { title: t("groupHotkeysSys"), items: [] },
    overview: { title: t("groupHotkeysOverview"), items: [] },
    pocket: { title: t("groupHotkeysPocket"), items: [] },
    workspaces: { title: t("groupHotkeysWorkspaces"), items: [] },
    window: { title: t("groupHotkeysWindow"), items: [] }
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
  if (combos.length > 0) {
    html += `<div class="conflict-banner">
      <span class="conflict-banner-icon">!</span>
      <span>${escapeHtml(t("hotkeyConflictsSummary", { combos: combos.join(", ") }))}</span>
    </div>`;
  }
  for (const gKey in groups) {
    const group = groups[gKey];
    if (group.items.length === 0) continue;

    html += `<div class="settings-group">
      <div class="group-title">${group.title}</div>
      <div class="group-cards">`;

    group.items.forEach(item => {
      const isModified = JSON.stringify(item.assigned) !== JSON.stringify(item.defaults);
      const isRecording = recordingTarget && recordingTarget.actionKey === item.action.key;
      const hasConflict = conflicts.has(item.action.key);
      const titleHtml = hasConflict
        ? `${item.title} <span class="conflict-badge" title="${escapeHtml(t("hotkeyConflictBadge"))}">!</span>`
        : item.title;

      html += `<div class="keybind-row" data-action="${item.action.key}">
        <div class="setting-info">
          <div class="setting-title">${titleHtml}</div>
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
            <span class="chip-remove" onclick="removeKeybind('${item.action.key}', ${idx})" title="${escapeHtml(t("removeBind"))}">
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
  heldCustomModifier = "";
  recordingTarget = { actionKey: actionKey };
  renderPrimaryModifierBar();
  renderHotkeysList();
  sendToAhk("START_KEY_RECORDING", {});
}

function cancelRecording() {
  heldCustomModifier = "";
  recordingTarget = null;
  renderPrimaryModifierBar();
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
  heldCustomModifier = "";
  saveConfigToStorage();
  renderHotkeysList();
  sendToAhk("SET_SETTING", { key: `hotkeys.profiles.${getActiveProfileName()}.${actionKey}`, value: binds[actionKey] });
  sendToAhk("STOP_KEY_RECORDING", {});
}

function normalizeWebKeyToAhk(e) {
  if (e.key === "NumLock" || e.code === "NumLock") return "NumLock";
  if (e.key === "CapsLock" || e.code === "CapsLock") return "CapsLock";
  if (e.key === "ScrollLock" || e.code === "ScrollLock") return "ScrollLock";
  if (e.key === "Control" || e.key === "Ctrl") return "Ctrl";
  if (e.key === "Alt") return "Alt";
  if (e.key === "Shift") return "Shift";
  if (e.key === "Meta") return "Win";

  const codeMap = {
    ArrowLeft: "Left",
    ArrowRight: "Right",
    ArrowUp: "Up",
    ArrowDown: "Down",
    Space: "Space",
    Tab: "Tab",
    Enter: "Enter",
    Escape: "Escape",
    Backspace: "Backspace",
    Delete: "Delete",
    Insert: "Insert",
    Home: "Home",
    End: "End",
    PageUp: "PageUp",
    PageDown: "PageDown",
    Pause: "Pause"
  };

  const code = e.code || e.key || "";
  if (codeMap[code]) return codeMap[code];
  if (code.startsWith("Key")) return code.substring(3);
  if (code.startsWith("Digit")) return code.substring(5);
  if (code.startsWith("Numpad")) {
    const numSub = code.substring(6);
    if (numSub.length > 0 && !isNaN(numSub)) return numSub;
  }
  return code;
}

function isStandardModifierKey(keyName) {
  return ["Ctrl", "Alt", "Shift", "Win"].includes(keyName);
}

window.addEventListener("keyup", (e) => {
  if (!heldCustomModifier) return;
  const released = normalizeWebKeyToAhk(e);
  if (normalizeModToken(released) === normalizeModToken(heldCustomModifier)) {
    heldCustomModifier = "";
  }
});

window.addEventListener("mousedown", (e) => {
  if (!recordingTarget) return;

  if (e.target && e.target.classList.contains("recording-cancel")) {
    return;
  }

  e.preventDefault();
  e.stopPropagation();

  if (recordingTarget.actionKey === "__PRIMARY_MODIFIER__" || recordingTarget.actionKey === "window_mouse_modifier") {
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
  if (heldCustomModifier) parts.push(heldCustomModifier);
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

  if (recordingTarget.actionKey === "__PRIMARY_MODIFIER__" || recordingTarget.actionKey === "window_mouse_modifier") {
    return;
  }

  const wheelName = e.deltaY < 0 ? "WheelUp" : "WheelDown";
  const parts = [];
  if (heldCustomModifier) parts.push(heldCustomModifier);
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

  const keyName = normalizeWebKeyToAhk(e);

  if (keyName === "Escape" && !e.ctrlKey && !e.altKey && !e.shiftKey && !e.metaKey && !heldCustomModifier) {
    cancelRecording();
    return;
  }

  if (recordingTarget.actionKey === "__PRIMARY_MODIFIER__") {
    if (keyName) {
      applyPrimaryModifier(keyName);
    }
    return;
  }

  if (recordingTarget.actionKey === "window_mouse_modifier") {
    if (keyName === "NumLock" || isStandardModifierKey(keyName) || normalizeModToken(keyName) === normalizeModToken(getPrimaryModifier())) {
      const parts = [];
      if (heldCustomModifier && normalizeModToken(heldCustomModifier) !== normalizeModToken(keyName)) parts.push(heldCustomModifier);
      if (e.ctrlKey && keyName !== "Ctrl") parts.push("Ctrl");
      if (e.altKey && keyName !== "Alt") parts.push("Alt");
      if (e.shiftKey && keyName !== "Shift") parts.push("Shift");
      if (e.metaKey && keyName !== "Win") parts.push("Win");
      parts.push(keyName);
      commitRecordedKey(parts.join(" + "));
      return;
    }
  }

  const activePrimary = getPrimaryModifier();
  const isCustomPrefixKey =
    keyName === "NumLock" ||
    (!isStandardModifierKey(activePrimary) && normalizeModToken(keyName) === normalizeModToken(activePrimary));

  if (isCustomPrefixKey && !heldCustomModifier) {
    heldCustomModifier = keyName;
    return;
  }

  if (isStandardModifierKey(keyName)) {
    return;
  }

  const parts = [];
  if (heldCustomModifier && normalizeModToken(heldCustomModifier) !== normalizeModToken(keyName)) {
    parts.push(heldCustomModifier);
  }
  if (e.ctrlKey) parts.push("Ctrl");
  if (e.altKey) parts.push("Alt");
  if (e.shiftKey) parts.push("Shift");
  if (e.metaKey) parts.push("Win");

  parts.push(keyName);
  commitRecordedKey(parts.join(" + "));
});

if (window.chrome && window.chrome.webview) {
  window.chrome.webview.addEventListener("message", (event) => {
    let msg = event.data;
    if (typeof msg === "string") {
      try { msg = JSON.parse(msg); } catch (e) {}
    }
    if (msg && msg.action === "APP_INFO") {
      const versionEl = document.getElementById("app-version");
      if (versionEl) versionEl.textContent = "v" + msg.version;
    }
    if (msg && msg.action === "THEME") {
      applyTheme(msg);
    }
    if (msg && msg.action === "AUTOSTART_FAILED") {
      alert(t("autostartFailed"));
    }
    if (msg && msg.action === "SETTINGS_EXPORTED") {
      if (msg.ok) alert(t("settingsExported", { path: msg.path }));
      else alert(t("settingsExportFailed"));
    }
    if (msg && msg.action === "SETTINGS_IMPORTED") {
      alert(t("settingsImported"));
    }
    if (msg && msg.action === "SETTINGS_IMPORT_FAILED") {
      alert(t("settingsImportFailed"));
    }
    if (msg && msg.action === "LOAD_CONFIG" && msg.config) {
      currentConfig = deepMerge(window.DEFAULT_CONFIG, msg.config);
      if (currentConfig.language) {
        currentLang = currentConfig.language;
      }
      saveConfigToStorage();
      applyTheme(lastSystemTheme);
      setLanguage(currentLang);
      syncFormValues();
    }
  });
}

document.addEventListener("DOMContentLoaded", () => {
  const prefersDark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  applyTheme({
    dark: prefersDark,
    accent: "#0078D7",
    os: document.documentElement.getAttribute("data-os") || "win11"
  });
  renderLanguageOptions();
  syncFormValues();
  sendToAhk("SETTINGS_READY", {});
});
