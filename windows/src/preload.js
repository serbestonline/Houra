// Pencerelerle ana süreç arasındaki tek köprü: call ana süreçteki bir işi çağırır, on olayları dinler.
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('houra', {
  boot: ipcRenderer.sendSync('boot'),
  call: (name, ...args) => ipcRenderer.invoke('call', name, ...args),
  on: (channel, handler) => ipcRenderer.on(channel, (_event, ...args) => handler(...args)),
});
