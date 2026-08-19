import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root

  property var anchorItem: null
  property var host: null
  property var bar: null
  property var settings: null
  property bool opened: false

  property string activeTab: "todo" // "todo" | "in_progress" | "done" | "notes"
  property var allTasks: []
  property var allNotes: []
  property double now: Date.now()
  property string copyFeedbackText: ""
  property string feedbackTaskId: ""

  readonly property string jsonPath: Quickshell.env("HOME") + "/.local/share/to-do/tasks.json"
  readonly property string mdPath: Quickshell.env("HOME") + "/.local/share/to-do/tasks.md"

  readonly property var runningTask: {
    var list = root.allTasks || []
    for (var i = 0; i < list.length; i++) {
      if (list[i].timer && list[i].timer.isRunning) return list[i]
    }
    return null
  }
  readonly property bool hasRunningTask: runningTask !== null
  readonly property string activeTimerText: {
    if (!runningTask) return ""
    return formatSeconds(getLiveTime(runningTask, root.now))
  }

  readonly property color foreground: Color.popups.text
  readonly property color bg: Color.popups.background
  readonly property color borderCol: Color.popups.border
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    root.opened = true
    root.now = Date.now()
    root.feedbackTaskId = ""
    root.copyFeedbackText = ""
    reloadTasks()
    Qt.callLater(function() {
      if (itemInput) itemInput.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function reloadTasks() {
    readProc.running = true
  }

  function copyToClipboard(text, id) {
    if (!text) return
    copyProc.exec(["node", "-e", `
      const { execFileSync } = require('child_process');
      execFileSync('wl-copy', [], { input: process.argv[1] });
    `, text])
    root.feedbackTaskId = id || "global"
    root.copyFeedbackText = "✓ Copied!"
    feedbackTimer.restart()
  }

  function saveTasks() {
    var data = {
      version: 1,
      notes: root.allNotes,
      tasks: root.allTasks
    }
    writeProc.exec(["node", "-e", `
      const fs = require('fs');
      const path = require('path');
      const jsonP = "${root.jsonPath}";
      const mdP = "${root.mdPath}";
      const tasks = ${JSON.stringify(root.allTasks)};
      const notes = ${JSON.stringify(root.allNotes)};

      fs.mkdirSync(path.dirname(jsonP), { recursive: true });
      fs.writeFileSync(jsonP, JSON.stringify({ version: 1, notes, tasks }, null, 2));

      function fmtHuman(sec) {
        if (!sec || sec <= 0) return '0s';
        const h = Math.floor(sec / 3600);
        const m = Math.floor((sec % 3600) / 60);
        const s = sec % 60;
        if (h > 0) return h + 'h' + (m > 0 ? ' ' + m + 'm' : '');
        if (m > 0) return m + 'm' + (s > 0 ? ' ' + s + 's' : '');
        return s + 's';
      }

      let md = "# 📋 Tasks & Time Log\\n\\n";

      if (notes && notes.length > 0) {
        md += "## 📝 Notes & Checklists\\n";
        for (const n of notes) {
          const check = n.done ? "[x] " : "[ ] ";
          md += "- " + check + n.text + " <!-- id:" + n.id + " -->\\n";
        }
        md += "\\n";
      }

      md += "## 📋 To-Do\\n";
      const todos = tasks.filter(t => t.status === 'todo');
      if (todos.length === 0) md += "_No tasks_\\n";
      for (const t of todos) md += "- [ ] " + t.title + " <!-- id:" + t.id + " -->\\n";

      md += "\\n## ⚡ Progress\\n";
      const inProgs = tasks.filter(t => t.status === 'in_progress');
      if (inProgs.length === 0) md += "_No tasks_\\n";
      for (const t of inProgs) {
        const spent = t.timeSpentSeconds || 0;
        md += "- [/] " + t.title + " (spent: " + fmtHuman(spent) + ") <!-- id:" + t.id + " -->\\n";
      }

      md += "\\n## ✅ Done\\n";
      const dones = tasks.filter(t => t.status === 'done');
      if (dones.length === 0) md += "_No completed tasks_\\n";
      for (const t of dones) {
        const spent = t.timeSpentSeconds || 0;
        md += "- [x] " + t.title + " (completed in " + fmtHuman(spent) + ") <!-- id:" + t.id + " -->\\n";
      }

      fs.writeFileSync(mdP, md, 'utf-8');
    `])
  }

  function addTask(title) {
    if (!title || title.trim() === "") return
    var id = Math.random().toString(36).substring(2, 9)
    var newTask = {
      id: id,
      title: title.trim(),
      status: "todo",
      createdAt: new Date().toISOString(),
      completedAt: null,
      timeSpentSeconds: 0,
      timer: {
        isRunning: false,
        lastStartedAt: null
      }
    }
    var list = JSON.parse(JSON.stringify(root.allTasks))
    list.unshift(newTask)
    root.allTasks = list
    root.activeTab = "todo"
    saveTasks()
  }

  function addNote(text) {
    if (!text || text.trim() === "") return
    var id = Math.random().toString(36).substring(2, 9)
    var newNote = {
      id: id,
      text: text.trim(),
      done: false,
      createdAt: new Date().toISOString()
    }
    var list = JSON.parse(JSON.stringify(root.allNotes || []))
    list.unshift(newNote)
    root.allNotes = list
    saveTasks()
  }

  function toggleNoteDone(id) {
    var list = JSON.parse(JSON.stringify(root.allNotes || []))
    var note = list.find(n => n.id === id)
    if (note) {
      note.done = !note.done
      root.allNotes = list
      saveTasks()
    }
  }

  function deleteNote(id) {
    var list = (root.allNotes || []).filter(n => n.id !== id)
    root.allNotes = list
    saveTasks()
  }

  function moveTask(id, newStatus) {
    var list = JSON.parse(JSON.stringify(root.allTasks))
    var task = list.find(t => t.id === id)
    if (task) {
      if (task.timer && task.timer.isRunning) {
        stopTimerObj(task)
      }
      task.status = newStatus
      task.completedAt = newStatus === "done" ? new Date().toISOString() : null
      root.allTasks = list
      saveTasks()
    }
  }

  function toggleTimer(task) {
    var list = JSON.parse(JSON.stringify(root.allTasks))
    var t = list.find(item => item.id === task.id)
    if (!t) return

    if (!t.timer) {
      t.timer = { isRunning: false, lastStartedAt: null }
    }

    if (t.status === "todo") {
      t.status = "in_progress"
    }

    if (t.timer.isRunning) {
      stopTimerObj(t)
    } else {
      for (var i = 0; i < list.length; i++) {
        if (list[i].timer && list[i].timer.isRunning) {
          stopTimerObj(list[i])
        }
      }
      t.timer.isRunning = true
      t.timer.lastStartedAt = new Date().toISOString()
    }

    root.now = Date.now()
    root.allTasks = list
    saveTasks()
  }

  function stopTimerObj(t) {
    if (t.timer && t.timer.isRunning && t.timer.lastStartedAt) {
      var elapsed = Math.floor((Date.now() - new Date(t.timer.lastStartedAt).getTime()) / 1000)
      t.timeSpentSeconds = (t.timeSpentSeconds || 0) + Math.max(0, elapsed)
      t.timer.isRunning = false
      t.timer.lastStartedAt = null
    }
  }

  function deleteTask(id) {
    var list = root.allTasks.filter(t => t.id !== id)
    root.allTasks = list
    saveTasks()
  }

  function formatSpentHuman(sec) {
    var s = Math.max(0, Math.floor(sec || 0))
    if (s <= 0) return "0s"
    var hrs = Math.floor(s / 3600)
    var mins = Math.floor((sec % 3600) / 60)
    var remS = s % 60

    if (hrs > 0) {
      return hrs + "h" + (mins > 0 ? " " + mins + "m" : "")
    }
    if (mins > 0) {
      return mins + "m" + (remS > 0 ? " " + remS + "s" : "")
    }
    return remS + "s"
  }

  function formatCreationTime(isoStr, nowMs) {
    if (!isoStr) return ""
    var date = new Date(isoStr)
    var now = new Date(nowMs || Date.now())
    var diffSec = Math.floor((now.getTime() - date.getTime()) / 1000)
    var diffMin = Math.floor(diffSec / 60)
    var diffHours = Math.floor(diffMin / 60)

    var isToday = date.getDate() === now.getDate() &&
                  date.getMonth() === now.getMonth() &&
                  date.getFullYear() === now.getFullYear()

    var yesterday = new Date(now)
    yesterday.setDate(yesterday.getDate() - 1)
    var isYesterday = date.getDate() === yesterday.getDate() &&
                      date.getMonth() === yesterday.getMonth() &&
                      date.getFullYear() === yesterday.getFullYear()

    if (isToday) {
      if (diffSec < 45) return "just now"
      if (diffMin < 60) return diffMin + "m ago"
      return diffHours + "h ago"
    }

    if (isYesterday) {
      return "yesterday"
    }

    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return date.getDate() + " " + months[date.getMonth()]
  }

  function formatDoneBadge(task, nowMs) {
    if (!task) return "✓ Done"
    var spent = root.formatSpentHuman(task.timeSpentSeconds)
    var doneDateStr = task.completedAt || task.createdAt
    if (!doneDateStr) return "✓ " + spent

    var date = new Date(doneDateStr)
    var now = new Date(nowMs || Date.now())

    var isToday = date.getDate() === now.getDate() &&
                  date.getMonth() === now.getMonth() &&
                  date.getFullYear() === now.getFullYear()

    if (isToday) {
      return "✓ " + spent
    }

    var yesterday = new Date(now)
    yesterday.setDate(yesterday.getDate() - 1)
    var isYesterday = date.getDate() === yesterday.getDate() &&
                      date.getMonth() === yesterday.getMonth() &&
                      date.getFullYear() === yesterday.getFullYear()

    if (isYesterday) {
      return "✓ " + spent + " · yesterday"
    }

    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return "✓ " + spent + " · " + date.getDate() + " " + months[date.getMonth()]
  }

  function formatSeconds(totalSec) {
    var sec = Math.max(0, Math.floor(totalSec))
    var hrs = Math.floor(sec / 3600)
    var mins = Math.floor((sec % 3600) / 60)
    var s = sec % 60
    var pad = (n) => (n < 10 ? "0" : "") + n
    if (hrs > 0) return pad(hrs) + ":" + pad(mins) + ":" + pad(s)
    return pad(mins) + ":" + pad(s)
  }

  function getLiveTime(t, nowMs) {
    var total = (t && t.timeSpentSeconds) ? t.timeSpentSeconds : 0
    if (t && t.timer && t.timer.isRunning && t.timer.lastStartedAt) {
      var elapsed = Math.floor(((nowMs || Date.now()) - new Date(t.timer.lastStartedAt).getTime()) / 1000)
      total += Math.max(0, elapsed)
    }
    return total
  }

  Process {
    id: readProc
    command: ["node", "-e", `
      const fs = require('fs');
      const p = "${root.jsonPath}";
      if (fs.existsSync(p)) {
        try {
          const data = JSON.parse(fs.readFileSync(p, 'utf-8'));
          console.log(JSON.stringify(data));
        } catch(e) { console.log("{}"); }
      } else { console.log("{}"); }
    `]
    stdout: SplitParser {
      onRead: data => {
        try {
          const obj = JSON.parse(data);
          root.allTasks = obj.tasks || [];
          root.allNotes = obj.notes || [];
        } catch(e) {}
      }
    }
  }

  Process { id: writeProc }
  Process { id: copyProc }

  Timer {
    id: feedbackTimer
    interval: 1500
    repeat: false
    onTriggered: {
      root.feedbackTaskId = ""
      root.copyFeedbackText = ""
    }
  }

  Timer {
    interval: 500
    running: root.opened || root.hasRunningTask
    repeat: true
    onTriggered: {
      root.now = Date.now()
    }
  }

  Component.onCompleted: {
    reloadTasks()
  }

  property var currentItemsList: {
    if (root.activeTab === "notes") {
      return root.allNotes || []
    }
    var list = root.allTasks || []
    return list.filter(t => t.status === root.activeTab)
  }

  KeyboardPanel {
    id: popupPanel
    anchorItem: root.anchorItem
    owner: root.host || root
    bar: root.bar
    open: root.opened
    contentWidth: Style.space(420)
    contentHeight: Style.space(480)

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(10)

      // Header: Title & Copy Toast
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        Text {
          text: "◩ Tasks & Time Tracker"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          Layout.fillWidth: true
        }

        Text {
          text: root.copyFeedbackText
          color: Color.green
          font.family: root.fontFamily
          font.pixelSize: Style.font.small
          font.bold: true
          visible: root.copyFeedbackText.length > 0
        }
      }

      // Top Tabs: Guaranteed Equal Sizing (Exact 1/3 Width Each)
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(6)

        // To-Do Tab
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredWidth: 0
          Layout.minimumWidth: 0
          height: Style.space(30)
          radius: Style.space(7)
          color: root.activeTab === "todo" ? Style.tint(root.foreground, 0.08) : Style.tint(root.foreground, 0.03)
          border.color: root.activeTab === "todo" ? root.foreground : Style.tint(root.foreground, 0.15)
          border.width: root.activeTab === "todo" ? 1.5 : 1

          Text {
            anchors.centerIn: parent
            text: "to-do (" + (root.allTasks || []).filter(t => t.status === "todo").length + ")"
            color: root.activeTab === "todo" ? root.foreground : Style.tint(root.foreground, 0.7)
            font.family: root.fontFamily
            font.bold: root.activeTab === "todo"
            font.pixelSize: Style.font.small
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activeTab = "todo"
          }
        }

        // Progress Tab
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredWidth: 0
          Layout.minimumWidth: 0
          height: Style.space(30)
          radius: Style.space(7)
          color: root.activeTab === "in_progress" ? Style.tint(Color.yellow, 0.18) : Style.tint(root.foreground, 0.03)
          border.color: root.activeTab === "in_progress" ? Color.yellow : Style.tint(root.foreground, 0.15)
          border.width: root.activeTab === "in_progress" ? 1.5 : 1

          Text {
            anchors.centerIn: parent
            text: "progress (" + (root.allTasks || []).filter(t => t.status === "in_progress").length + ")"
            color: root.activeTab === "in_progress" ? Color.yellow : Style.tint(root.foreground, 0.7)
            font.family: root.fontFamily
            font.bold: root.activeTab === "in_progress"
            font.pixelSize: Style.font.small
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activeTab = "in_progress"
          }
        }

        // Done Tab
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredWidth: 0
          Layout.minimumWidth: 0
          height: Style.space(30)
          radius: Style.space(7)
          color: root.activeTab === "done" ? Style.tint(Color.green, 0.18) : Style.tint(root.foreground, 0.03)
          border.color: root.activeTab === "done" ? Color.green : Style.tint(root.foreground, 0.15)
          border.width: root.activeTab === "done" ? 1.5 : 1

          Text {
            anchors.centerIn: parent
            text: "done (" + (root.allTasks || []).filter(t => t.status === "done").length + ")"
            color: root.activeTab === "done" ? Color.green : Style.tint(root.foreground, 0.7)
            font.family: root.fontFamily
            font.bold: root.activeTab === "done"
            font.pixelSize: Style.font.small
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activeTab = "done"
          }
        }
      }

      // Header Action Row: Quick Add Input + Note Toggle Button
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(6)

        // Quick-Add Input
        Rectangle {
          Layout.fillWidth: true
          height: Style.space(34)
          radius: Style.space(7)
          color: Style.tint(root.foreground, 0.03)
          border.color: itemInput.activeFocus ? root.foreground : Style.tint(root.foreground, 0.15)
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(6)

            Text {
              text: "+"
              color: Style.tint(root.foreground, 0.5)
              font.family: root.fontFamily
              font.bold: true
              font.pixelSize: Style.font.body
            }

            QQC.TextField {
              id: itemInput
              Layout.fillWidth: true
              placeholderText: root.activeTab === "notes" ? "Add new note / item..." : "Add new task and press Enter..."
              placeholderTextColor: Style.tint(root.foreground, 0.4)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              background: null
              leftPadding: 0
              rightPadding: 0
              topPadding: 0
              bottomPadding: 0
              onAccepted: {
                if (root.activeTab === "notes") {
                  root.addNote(itemInput.text)
                } else {
                  root.addTask(itemInput.text)
                }
                itemInput.text = ""
              }
              Keys.onEscapePressed: root.close()
            }
          }
        }

        // Clean Note Mode Button [Note (count)]
        Rectangle {
          height: Style.space(34)
          radius: Style.space(7)
          color: root.activeTab === "notes" ? Style.tint(root.foreground, 0.08) : Style.tint(root.foreground, 0.03)
          border.color: root.activeTab === "notes" ? root.foreground : Style.tint(root.foreground, 0.15)
          border.width: root.activeTab === "notes" ? 1.5 : 1
          Layout.preferredWidth: headerNoteLabel.implicitWidth + Style.space(20)

          Text {
            id: headerNoteLabel
            anchors.centerIn: parent
            text: "Note (" + (root.allNotes || []).length + ")"
            color: root.activeTab === "notes" ? root.foreground : Style.tint(root.foreground, 0.8)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: root.activeTab === "notes"
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.activeTab === "notes") {
                root.activeTab = "todo"
              } else {
                root.activeTab = "notes"
              }
            }
          }
        }
      }

      // Card List View (Unified exact style for both Tasks and Notes)
      ListView {
        id: itemsListView
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: Style.space(6)
        model: root.currentItemsList

        delegate: Rectangle {
          id: itemCard
          width: itemsListView.width
          implicitHeight: Math.max(Style.space(44), itemRow.implicitHeight + Style.space(12))
          height: implicitHeight
          radius: Style.space(8)

          property var itemObj: modelData
          property bool isNoteItem: root.activeTab === "notes"
          property bool isTaskRunning: !isNoteItem && itemObj && itemObj.timer && itemObj.timer.isRunning === true
          property int liveDuration: isNoteItem ? 0 : root.getLiveTime(itemObj, root.now)
          property bool isHovered: cardMouse.containsMouse
          property bool isItemFeedback: root.feedbackTaskId === (itemObj ? itemObj.id : "")
          property bool isNoteDone: isNoteItem && itemObj && itemObj.done === true

          color: isTaskRunning ? Style.tint(Color.green, 0.08) : (isHovered ? Style.tint(root.foreground, 0.06) : Style.tint(root.foreground, 0.03))
          border.color: isTaskRunning ? Color.green : (isHovered ? Style.tint(root.foreground, 0.25) : Style.tint(root.foreground, 0.12))
          border.width: isTaskRunning ? 1.5 : 1

          MouseArea {
            id: cardMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
          }

          RowLayout {
            id: itemRow
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)

            // Left Action Box: Play/Pause/Restart for tasks; Toggle Checkbox for notes
            Rectangle {
              width: Style.space(26)
              height: Style.space(26)
              radius: isNoteItem ? Style.space(5) : Style.space(6)
              Layout.alignment: Qt.AlignVCenter
              color: isNoteItem
                ? (isNoteDone ? Style.tint(Color.green, 0.18) : Style.tint(root.foreground, 0.06))
                : (itemObj.status === "done" ? Style.tint(root.foreground, 0.08) : (isTaskRunning ? Style.tint(Color.green, 0.2) : Style.tint(root.foreground, 0.06)))
              border.color: isNoteItem
                ? (isNoteDone ? Color.green : Style.tint(root.foreground, 0.2))
                : (itemObj.status === "done" ? root.foreground : (isTaskRunning ? Color.green : Style.tint(root.foreground, 0.2)))
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: isNoteItem
                  ? (isNoteDone ? "✓" : "")
                  : (itemObj.status === "done" ? "↺" : (isTaskRunning ? "⏸" : "▶"))
                color: isNoteItem
                  ? (isNoteDone ? Color.green : root.foreground)
                  : (itemObj.status === "done" ? root.foreground : (isTaskRunning ? Color.green : root.foreground))
                font.family: root.fontFamily
                font.bold: true
                font.pixelSize: Style.font.body
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (isNoteItem) {
                    root.toggleNoteDone(itemObj.id)
                  } else {
                    if (itemObj.status === "done") {
                      root.moveTask(itemObj.id, "todo")
                    } else {
                      root.toggleTimer(itemObj)
                    }
                  }
                }
              }
            }

            // Center Content (Title for tasks / Markdown text for notes)
            Text {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              wrapMode: Text.Wrap
              text: isNoteItem ? (itemObj.text || "") : (itemObj.title || "")
              textFormat: isNoteItem ? Text.MarkdownText : Text.PlainText
              color: (isNoteItem && isNoteDone) || (!isNoteItem && itemObj.status === "done") ? Style.tint(root.foreground, 0.4) : root.foreground
              font.family: root.fontFamily
              font.bold: (!isNoteItem && itemObj.status !== "done") || (isNoteItem && !isNoteDone)
              font.pixelSize: Style.font.body
              font.strikeout: (isNoteItem && isNoteDone) || (!isNoteItem && itemObj.status === "done")
            }

            // In-Progress Quick Checkmark to complete task (Tasks only)
            Rectangle {
              width: Style.space(22)
              height: Style.space(22)
              radius: Style.space(5)
              color: Style.tint(Color.green, 0.15)
              border.color: Color.green
              border.width: 1
              visible: !isNoteItem && itemObj.status === "in_progress"
              Layout.alignment: Qt.AlignVCenter

              Text {
                anchors.centerIn: parent
                text: "✓"
                color: Color.green
                font.family: root.fontFamily
                font.pixelSize: Style.font.small
                font.bold: true
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.moveTask(itemObj.id, "done")
              }
            }

            // Copy Icon Button (Hover-only on Note cards, shows clipboard glyph / checkmark feedback)
            Rectangle {
              width: Style.space(22)
              height: Style.space(22)
              radius: Style.space(5)
              color: isItemFeedback ? Style.tint(Color.green, 0.18) : (copyMouse.containsMouse ? Style.tint(root.foreground, 0.12) : Style.tint(root.foreground, 0.06))
              border.color: isItemFeedback ? Color.green : Style.tint(root.foreground, 0.18)
              border.width: 1
              visible: isNoteItem && (isHovered || isItemFeedback)
              Layout.alignment: Qt.AlignVCenter

              Text {
                id: copyLabel
                anchors.centerIn: parent
                text: isItemFeedback ? "✓" : "\uf0c5"
                color: isItemFeedback ? Color.green : Style.tint(root.foreground, 0.85)
                font.family: root.fontFamily
                font.pixelSize: isItemFeedback ? Style.font.small : Style.font.micro
                font.bold: isItemFeedback
              }

              MouseArea {
                id: copyMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.copyToClipboard(itemObj.text, itemObj.id)
              }
            }

            // Right: Time Badge (Tasks only)
            Rectangle {
              visible: !isNoteItem
              height: Style.space(20)
              radius: Style.space(4)
              color: isTaskRunning ? Style.tint(Color.green, 0.18) : (itemObj.status === "in_progress" ? Style.tint(Color.yellow, 0.15) : Style.tint(root.foreground, 0.05))
              border.color: isTaskRunning ? Color.green : (itemObj.status === "in_progress" ? Color.yellow : Style.tint(root.foreground, 0.15))
              border.width: 1
              Layout.preferredWidth: timeText.implicitWidth + Style.space(10)
              Layout.alignment: Qt.AlignVCenter

              Text {
                id: timeText
                anchors.centerIn: parent
                text: itemObj.status === "in_progress"
                  ? (isTaskRunning ? "⏱ " : "⏸ ") + root.formatSeconds(liveDuration)
                  : (itemObj.status === "done"
                    ? root.formatDoneBadge(itemObj, root.now)
                    : root.formatCreationTime(itemObj.createdAt, root.now))
                color: isTaskRunning ? Color.green : (itemObj.status === "in_progress" ? Color.yellow : Style.tint(root.foreground, 0.75))
                font.family: root.fontFamily
                font.pixelSize: Style.font.micro
                font.bold: isTaskRunning || itemObj.status === "done"
              }
            }

            // Delete Button ✕ (Hover-only)
            Rectangle {
              width: Style.space(18)
              height: Style.space(18)
              radius: Style.space(4)
              color: "transparent"
              visible: isHovered
              Layout.alignment: Qt.AlignVCenter

              Text {
                anchors.centerIn: parent
                text: "✕"
                color: Color.red
                font.pixelSize: Style.font.small
                font.bold: true
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (isNoteItem) {
                    root.deleteNote(itemObj.id)
                  } else {
                    root.deleteTask(itemObj.id)
                  }
                }
              }
            }
          }
        }

        // Empty State
        Rectangle {
          anchors.fill: parent
          radius: Style.space(8)
          color: Style.tint(root.foreground, 0.02)
          border.color: Style.tint(root.foreground, 0.08)
          border.width: 1
          visible: root.currentItemsList.length === 0

          Text {
            anchors.centerIn: parent
            text: root.activeTab === "notes" ? "No notes yet.\nType above to add one!" : "No tasks here.\nType above to add one!"
            color: Style.tint(root.foreground, 0.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
