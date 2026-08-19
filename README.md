# ◩ Tasks & Time Tracker (Omarchy Bar Plugin)

A native [Omarchy](https://omarchy.org/) Quickshell bar widget for fast task management, live stopwatch time tracking, and Markdown notes.

<p align="center">
  <img src="assets/omarchy-todo.png" alt="Tasks & Time Tracker" width="380">
  <img src="assets/omarchy-notes.png" alt="Markdown Notes & Checklists" width="380">
</p>

## ✨ Features

- **3-Stage Task Flow**:
  - **`to-do`**: Shows task creation timestamp (`just now`, `5m ago`, `yesterday`, `15 Aug`). Click `▶` to start and move to progress.
  - **`progress`**: Live ticking stopwatch (`⏱ 00:54`) with 1-click pause (`⏸`) and instant completion (`✓`).
  - **`done`**: Displays total elapsed time spent on each task (`✓ 30m`, `✓ 1h 15m`). Click `↺` to reset back to To-Do.
- **📝 Markdown Notes & Checklists**:
  - Full Markdown formatting support.
  - Interactive checkboxes `[ ]` / `[✓]` with strikeout formatting.
  - 1-click **`Copy`** button (copies directly to Wayland clipboard with `wl-copy`).
- **Seamless Omarchy Integration**:
  - **Theme Adaptive**: Automatically adapts to any active Omarchy theme (Catppuccin, Gruvbox, Nord, Tokyo Night, Flexoki, etc.) using dynamic theme tokens.
  - Native layer-shell popup panel attached to the top bar icon (`\uf0ae`).
  - 100% in-memory reactivity with **0% idle CPU** and zero background polling subprocesses.
- **Persistent Storage**:
  - Tasks & notes: `~/.local/share/to-do/tasks.json`
  - Auto-generated Markdown log: `~/.local/share/to-do/tasks.md`

## 🚀 Installation

1. Copy the plugin files to your Omarchy user plugins directory:
   ```bash
   mkdir -p ~/.config/omarchy/plugins/limon.todo
   cp -r ./*.qml ./manifest.json ~/.config/omarchy/plugins/limon.todo/
   ```

2. Add `"limon.todo"` to your bar layout in `~/.config/omarchy/shell.json`:
   ```json
   {
     "bar": {
       "layout": {
         "right": [
           { "id": "limon.todo" }
         ]
       }
     }
   }
   ```

3. Restart the Omarchy shell:
   ```bash
   omarchy restart shell
   ```

## 📂 Project Structure

```
omarchy-todo/
├── assets/
│   ├── omarchy-todo.png   # Task view preview
│   └── omarchy-notes.png  # Notes & checklists preview
├── manifest.json          # Omarchy plugin registration manifest
├── BarWidget.qml          # Native top bar icon & tooltip handler
├── Panel.qml              # Popup layer-shell panel (Tasks, Timer, Notes)
├── LICENSE                # MIT License
├── README.md              # Documentation & setup guide
└── .gitignore
```
