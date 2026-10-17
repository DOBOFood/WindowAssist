let currentModel = null;
let isDraggingWindow = false;
let selectedHwnds = new Set();
let dragGhostEl = null;
let activeDragHwnds = [];

function clearSelection() {
  if (selectedHwnds.size === 0) return;
  selectedHwnds.clear();
  document.querySelectorAll('.app-item.selected').forEach(el => el.classList.remove('selected'));
}

function toggleAppSelection(hwnd, appItem) {
  if (selectedHwnds.has(hwnd)) {
    selectedHwnds.delete(hwnd);
    appItem.classList.remove('selected');
  } else {
    selectedHwnds.add(hwnd);
    appItem.classList.add('selected');
  }
}

function sendToAhk(msg) {
  if (window.ahk && typeof window.ahk.send === 'function') {
    window.ahk.send(msg);
  } else if (window.chrome && window.chrome.webview) {
    window.chrome.webview.postMessage(typeof msg === 'object' ? JSON.stringify(msg) : msg);
  }
}

// 1. Прием данных от AutoHotkey
if (window.chrome && window.chrome.webview) {
  window.chrome.webview.addEventListener('message', (event) => {
    let msg = event.data;
    if (typeof msg === 'string') {
      try { msg = JSON.parse(msg); } catch (e) {}
    }
    if (msg && msg.action === 'INIT_STATE') {
      currentModel = msg;
      renderGrid(msg);
    }
  });
}

// 2. Сигнал AutoHotkey о том, что страница готова принимать данные
function notifyReady() {
  sendToAhk({ action: 'DOM_READY' });
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', notifyReady);
} else {
  notifyReady();
}

// 3. Отрисовка сетки рабочих столов
function renderGrid(model) {
  const container = document.getElementById('workspaces-grid');
  if (!container) return;

  // Очищаем из выделения окна, которых больше нет
  const allExistingHwnds = new Set();
  if (model.workspaces && Array.isArray(model.workspaces)) {
    model.workspaces.forEach(ws => {
      if (ws.apps && Array.isArray(ws.apps)) {
        ws.apps.forEach(a => allExistingHwnds.add(a.hwnd));
      }
    });
  }
  for (const h of selectedHwnds) {
    if (!allExistingHwnds.has(h)) selectedHwnds.delete(h);
  }

  container.innerHTML = '';

  if (!model.workspaces || !Array.isArray(model.workspaces)) return;

  model.workspaces.forEach((ws) => {
    const col = document.createElement('div');
    col.className = 'workspace-column';

    // Карточка рабочего стола
    const card = document.createElement('div');
    card.className = `workspace-card ${ws.isCurrent ? 'current' : ''}`;
    card.dataset.wsId = ws.id;

    const num = document.createElement('div');
    num.className = 'ws-number';
    num.innerText = ws.id;
    card.appendChild(num);

    // Скрытый оверлей под превью
    const previewImg = document.createElement('img');
    previewImg.className = 'card-preview-overlay';
    previewImg.id = `preview-${ws.id}`;
    card.appendChild(previewImg);

    // Переход на стол по клику
    card.addEventListener('click', () => {
      sendToAhk({ action: 'SWITCH_WORKSPACE', targetWs: ws.id });
    });

    // Удаление стола по ПКМ
    card.addEventListener('contextmenu', (e) => {
      e.preventDefault();
      sendToAhk({ action: 'DELETE_WORKSPACE', targetWs: ws.id });
    });

    // Зона Drag & Drop на родительской колонке стола
    col.addEventListener('dragover', (e) => {
      e.preventDefault();
      col.classList.add('drag-over-col');
    });
    col.addEventListener('dragleave', (e) => {
      if (!col.contains(e.relatedTarget)) {
        col.classList.remove('drag-over-col');
      }
    });
    col.addEventListener('drop', (e) => {
      e.preventDefault();
      col.classList.remove('drag-over-col');

      let hwnds = (activeDragHwnds && activeDragHwnds.length) ? [...activeDragHwnds] : [];
      if (!hwnds.length) {
        const rawHwnds = e.dataTransfer.getData('application/json');
        if (rawHwnds) {
          try { hwnds = JSON.parse(rawHwnds); } catch (_) {}
        }
      }
      if (!hwnds || !hwnds.length) {
        const raw = e.dataTransfer.getData('text/plain');
        if (raw) {
          const h = parseInt(raw, 10);
          if (!isNaN(h)) hwnds = [h];
        }
      }

      if (hwnds && hwnds.length) {
        sendToAhk({ action: 'MOVE_WINDOW', hwnds: hwnds, hwnd: hwnds[0], targetWs: ws.id });
        clearSelection();
      }
    });

    // Дублируем слушатели на card и appList
    card.addEventListener('dragover', (e) => {
      e.preventDefault();
      col.classList.add('drag-over-col');
    });
    card.addEventListener('drop', (e) => {
      e.preventDefault();
      col.classList.remove('drag-over-col');
      let hwnds = [];
      const rawHwnds = e.dataTransfer.getData('application/json');
      if (rawHwnds) {
        try { hwnds = JSON.parse(rawHwnds); } catch (_) {}
      }
      if (!hwnds || !hwnds.length) {
        const raw = e.dataTransfer.getData('text/plain');
        if (raw) {
          const h = parseInt(raw, 10);
          if (!isNaN(h)) hwnds = [h];
        }
      }
      if (hwnds && hwnds.length) {
        sendToAhk({ action: 'MOVE_WINDOW', hwnds: hwnds, hwnd: hwnds[0], targetWs: ws.id });
        clearSelection();
      }
    });

    col.appendChild(card);

    // Список приложений под столом
    const appList = document.createElement('div');
    appList.className = 'app-list';

    appList.addEventListener('dragover', (e) => {
      e.preventDefault();
      col.classList.add('drag-over-col');
    });
    appList.addEventListener('drop', (e) => {
      e.preventDefault();
      col.classList.remove('drag-over-col');
      let hwnds = [];
      const rawHwnds = e.dataTransfer.getData('application/json');
      if (rawHwnds) {
        try { hwnds = JSON.parse(rawHwnds); } catch (_) {}
      }
      if (!hwnds || !hwnds.length) {
        const raw = e.dataTransfer.getData('text/plain');
        if (raw) {
          const h = parseInt(raw, 10);
          if (!isNaN(h)) hwnds = [h];
        }
      }
      if (hwnds && hwnds.length) {
        sendToAhk({ action: 'MOVE_WINDOW', hwnds: hwnds, hwnd: hwnds[0], targetWs: ws.id });
        clearSelection();
      }
    });

    if (ws.apps && Array.isArray(ws.apps)) {
      ws.apps.forEach((app) => {
        const appItem = document.createElement('div');
        appItem.className = `app-item ${selectedHwnds.has(app.hwnd) ? 'selected' : ''}`;
        appItem.draggable = true;

        const icon = document.createElement('img');
        icon.className = 'app-icon';
        icon.src = app.icon || 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg"/>';

        const title = document.createElement('span');
        title.className = 'app-title';
        title.innerText = app.title;

        appItem.appendChild(icon);
        appItem.appendChild(title);

        // Клик по приложению
        appItem.addEventListener('click', (e) => {
          if (e.button === 0) {
            if (e.ctrlKey || e.metaKey) {
              toggleAppSelection(app.hwnd, appItem);
              return;
            }
            if (selectedHwnds.size > 0) {
              clearSelection();
            }
            sendToAhk({ action: 'SWITCH_TO_WINDOW', hwnd: app.hwnd });
          }
        });

        // Мгновенный показ превью при наведении
        appItem.addEventListener('mouseenter', () => {
          if (!isDraggingWindow && app.preview) {
            previewImg.src = app.preview;
            previewImg.classList.add('active');
          }
        });
        appItem.addEventListener('mouseleave', () => {
          previewImg.classList.remove('active');
        });

        // Перетаскивание
        appItem.addEventListener('dragstart', (e) => {
          isDraggingWindow = true;
          previewImg.classList.remove('active');

          if (!selectedHwnds.has(app.hwnd)) {
            clearSelection();
            selectedHwnds.add(app.hwnd);
            appItem.classList.add('selected');
          }

          const hwndsArray = Array.from(selectedHwnds);
          activeDragHwnds = hwndsArray;
          e.dataTransfer.setData('application/json', JSON.stringify(hwndsArray));
          e.dataTransfer.setData('text/plain', String(app.hwnd));

          document.querySelectorAll('.app-item.selected').forEach(el => el.classList.add('dragging'));

          if (hwndsArray.length > 1) {
            if (dragGhostEl) dragGhostEl.remove();

            const ghost = document.createElement('div');
            ghost.className = 'drag-multi-ghost';

            const badge = document.createElement('div');
            badge.className = 'ghost-badge';
            badge.textContent = hwndsArray.length;
            ghost.appendChild(badge);

            const iconsContainer = document.createElement('div');
            iconsContainer.className = 'ghost-icons';

            const iconMap = new Map();
            if (currentModel && currentModel.workspaces) {
              currentModel.workspaces.forEach(w => {
                if (w.apps) {
                  w.apps.forEach(a => {
                    if (a.icon) iconMap.set(a.hwnd, a.icon);
                  });
                }
              });
            }

            hwndsArray.slice(0, 4).forEach(h => {
              const gIcon = document.createElement('img');
              gIcon.className = 'ghost-icon';
              gIcon.src = iconMap.get(h) || 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg"/>';
              iconsContainer.appendChild(gIcon);
            });

            ghost.appendChild(iconsContainer);
            document.body.appendChild(ghost);
            dragGhostEl = ghost;

            e.dataTransfer.setDragImage(ghost, 20, 20);
          }
        });

        appItem.addEventListener('dragend', () => {
          isDraggingWindow = false;
          activeDragHwnds = [];
          document.querySelectorAll('.app-item.dragging').forEach(el => el.classList.remove('dragging'));
          if (dragGhostEl) {
            dragGhostEl.remove();
            dragGhostEl = null;
          }
        });

        appList.appendChild(appItem);
      });
    }

    col.appendChild(appList);
    container.appendChild(col);
  });

  // Карточка добавления нового рабочего стола (+)
  const addCol = document.createElement('div');
  addCol.className = 'workspace-column';
  const addCard = document.createElement('div');
  addCard.className = 'workspace-card add-card';
  addCard.innerHTML = '<div class="ws-number">+</div>';
  addCard.addEventListener('click', () => {
    sendToAhk({ action: 'ADD_WORKSPACE' });
  });
  addCol.appendChild(addCard);
  container.appendChild(addCol);
}

function onBackdropClick(e) {
  if (e.target.id === 'backdrop') {
    sendToAhk({ action: 'CLOSE_OVERVIEW' });
  }
}

// 4. Ресайз контейнера по горизонтали с шагом 10px
const container = document.getElementById('grid-container');
const handle = document.getElementById('resize-handle');
let isResizing = false;
let startX = 0;
let startWidth = 0;

if (container) {
  container.addEventListener('click', (e) => {
    if (!e.ctrlKey && !e.metaKey && !e.target.closest('.app-item')) {
      clearSelection();
    }
  });
}

if (handle && container) {
  handle.addEventListener('mousedown', (e) => {
    isResizing = true;
    startX = e.clientX;
    startWidth = container.offsetWidth;
    handle.classList.add('active');
    document.body.style.cursor = 'ew-resize';
    e.preventDefault();
  });

  window.addEventListener('mousemove', (e) => {
    if (!isResizing) return;
    const rawDx = e.clientX - startX;
    const snappedDx = Math.round(rawDx / 10) * 10;
    const newWidth = Math.max(360, startWidth + snappedDx);
    container.style.width = `${newWidth}px`;
  });

  window.addEventListener('mouseup', () => {
    if (isResizing) {
      isResizing = false;
      handle.classList.remove('active');
      document.body.style.cursor = 'default';
    }
  });
}

// 5. Закрытие по клавише Escape
window.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    sendToAhk({ action: 'CLOSE_OVERVIEW' });
  }
});
