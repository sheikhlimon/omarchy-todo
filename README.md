# ◩ Tasks & Time Tracker

A native [Omarchy](https://omarchy.org/) bar plugin for task management, live stopwatch tracking, and Markdown notes.

<p align="center">
  <img src="assets/omarchy-todo.png" alt="Tasks & Time Tracker" width="380">
  <img src="assets/omarchy-notes.png" alt="Markdown Notes & Checklists" width="380">
</p>

## Features

- **3-Stage Workflow**: `to-do`, `progress` (live stopwatch), and `done` (total time spent).
- **Markdown Notes**: Fast scratchpad with interactive checkboxes and one-click copy.
- **Smart Hover**: Contextual actions (`▶`, `⏸`, `✓`, `↺`, `Copy`, `✕`) reveal on hover.
- **Theme Adaptive**: Automatically matches your active Omarchy color scheme and typography.
- **Zero Overhead**: Native in-process Quickshell layer with persistent storage in `~/.local/share/to-do/`.

## Install

1. Copy the plugin into your Omarchy plugins directory:
   ```bash
   mkdir -p ~/.config/omarchy/plugins/limon.todo
   cp -r ./*.qml ./manifest.json ~/.config/omarchy/plugins/limon.todo/
   ```

2. Add `"limon.todo"` to `~/.config/omarchy/shell.json` and reload:
   ```bash
   omarchy restart shell
   ```

## License

[MIT](LICENSE)
