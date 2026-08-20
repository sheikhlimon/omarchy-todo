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
  property bool opened: false

  property string activeTab: "todo" // "todo" | "in_progress" | "done" | "notes"
  property var allTasks: []
  property var allNotes: []
  property int dataVersion: 0
  property double now: Date.now()
  property string copyFeedbackText: ""
  property string feedbackTaskId: ""

  readonly property string jsonPath: Quickshell.env("HOME") + "/.local/share/to-do/tasks.json"
  readonly property string mdPath: Quickshell.env("HOME") + "/.local/share/to-do/tasks.md"
  readonly property string helperPath: Qt.resolvedUrl("helper.sh").toString().replace("file://", "")

  readonly property var runningTask: {
    var list = root.allTasks || []
    for (var i = 0; i < list.length; i++) {
      if (list[i].timer && list[i].timer.isRunning) return list[i]
    }
    return null
  }
  readonly property bool hasRunningTask: runningTask !== null

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
    copyProc.exec([root.helperPath, "copy", text])
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
    writeProc.exec([root.helperPath, "write", root.jsonPath, root.mdPath, JSON.stringify(root.allNotes), JSON.stringify(root.allTasks)])
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

  property string editingId: ""

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

  function updateNote(id, text) {
    if (!text || text.trim() === "") return
    for (var i = 0; i < root.allNotes.length; i++) {
      if (root.allNotes[i].id === id) {
        root.allNotes[i].text = text.trim()
        break
      }
    }
    root.dataVersion++
    saveTasks()
  }

  function updateTask(id, title) {
    if (!title || title.trim() === "") return
    for (var i = 0; i < root.allTasks.length; i++) {
      if (root.allTasks[i].id === id) {
        root.allTasks[i].title = title.trim()
        break
      }
    }
    root.dataVersion++
    saveTasks()
  }

  function toggleNoteDone(id) {
    for (var i = 0; i < root.allNotes.length; i++) {
      if (root.allNotes[i].id === id) {
        root.allNotes[i].done = !root.allNotes[i].done
        break
      }
    }
    root.dataVersion++
    saveTasks()
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
    var idx = -1;
    for (var i = 0; i < root.allTasks.length; i++) {
      if (root.allTasks[i].id === task.id) {
        idx = i;
        break;
      }
    }
    if (idx === -1) return

    if (!root.allTasks[idx].timer) {
      root.allTasks[idx].timer = { isRunning: false, lastStartedAt: null }
    }

    var listChanged = false;
    if (root.allTasks[idx].status === "todo") {
      root.allTasks[idx].status = "in_progress"
      listChanged = true;
    }

    if (root.allTasks[idx].timer.isRunning) {
      stopTimerObj(root.allTasks[idx])
    } else {
      for (var j = 0; j < root.allTasks.length; j++) {
        if (root.allTasks[j].timer && root.allTasks[j].timer.isRunning) {
          stopTimerObj(root.allTasks[j])
        }
      }
      root.allTasks[idx].timer.isRunning = true
      root.allTasks[idx].timer.lastStartedAt = new Date().toISOString()
    }

    root.now = Date.now()
    if (listChanged) {
      root.allTasks = root.allTasks.slice()
    } else {
      root.dataVersion++
    }
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
    command: [root.helperPath, "read", root.jsonPath]
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
            text: "notes (" + (root.allNotes || []).length + ")"
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

      // Card List View
      ListView {
        id: itemsListView
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: Style.space(6)
        cacheBuffer: 3000
        model: root.currentItemsList
        QQC.ScrollBar.vertical: QQC.ScrollBar {
          active: true
        }

        delegate: Rectangle {
          id: itemCard
          width: itemsListView.width
          implicitHeight: Math.max(Style.space(44), itemRow.implicitHeight + Style.space(12))
          height: implicitHeight
          radius: Style.space(8)

          property var itemObj: { var _ = root.dataVersion; return root.currentItemsList[index] || modelData }
          property string itemStatus: { var _ = root.dataVersion; return itemObj ? (itemObj.status || "") : "" }
          property bool isNoteItem: root.activeTab === "notes"
          property bool isTaskRunning: { var _ = root.dataVersion; return !isNoteItem && itemObj && itemObj.timer && itemObj.timer.isRunning === true }
          property int liveDuration: { var _ = root.dataVersion; return isNoteItem ? 0 : root.getLiveTime(itemObj, root.now) }
          property bool isHovered: cardHover.hovered
          property bool isItemFeedback: root.feedbackTaskId === (itemObj ? itemObj.id : "")

          color: isTaskRunning ? Style.tint(Color.green, 0.08) : (isHovered ? Style.tint(root.foreground, 0.06) : Style.tint(root.foreground, 0.03))
          border.color: isTaskRunning ? Color.green : (isHovered ? Style.tint(root.foreground, 0.25) : Style.tint(root.foreground, 0.12))
          border.width: isTaskRunning ? 1.5 : 1

          HoverHandler {
            id: cardHover
          }

          RowLayout {
            id: itemRow
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            anchors.topMargin: Style.space(6)
            anchors.bottomMargin: Style.space(6)
            spacing: Style.space(8)

            // Left Action Box: Play/Pause/Restart for tasks
            Rectangle {
              width: Style.space(26)
              height: Style.space(26)
              radius: Style.space(6)
              Layout.alignment: Qt.AlignVCenter
              visible: !isNoteItem
              color: itemStatus === "done" ? Style.tint(Color.blue, 0.15) : (isTaskRunning ? Style.tint(Color.green, 0.2) : Style.tint(root.foreground, 0.06))
              border.color: itemStatus === "done" ? Color.blue : (isTaskRunning ? Color.green : Style.tint(root.foreground, 0.2))
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: itemStatus === "done" ? "↺" : (isTaskRunning ? "⏸" : "▶")
                color: itemStatus === "done" ? Color.blue : (isTaskRunning ? Color.green : root.foreground)
                font.family: root.fontFamily
                font.bold: true
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: leftBtnMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (!isNoteItem) {
                    if (itemStatus === "done") {
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
              visible: root.editingId !== itemObj.id
              Layout.fillWidth: true
              Layout.alignment: isNoteItem ? Qt.AlignTop : Qt.AlignVCenter
              wrapMode: Text.Wrap
              text: { var _ = root.dataVersion; return isNoteItem ? (itemObj.text || "") : (itemObj.title || "") }
              textFormat: isNoteItem ? Text.MarkdownText : Text.PlainText
              color: (!isNoteItem && itemStatus === "done") ? Style.tint(root.foreground, 0.4) : root.foreground
              font.family: root.fontFamily
              font.weight: (!isNoteItem && itemStatus !== "done") || isNoteItem ? 550 : 400
              font.pixelSize: Style.font.body
              font.strikeout: !isNoteItem && itemStatus === "done"
            }

            QQC.TextArea {
              id: editField
              visible: root.editingId === itemObj.id
              Layout.fillWidth: true
              Layout.alignment: isNoteItem ? Qt.AlignTop : Qt.AlignVCenter
              wrapMode: Text.Wrap
              text: { var _ = root.dataVersion; return isNoteItem ? (itemObj.text || "") : (itemObj.title || "") }
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              background: null
              leftPadding: 0
              rightPadding: 0
              topPadding: 0
              bottomPadding: 0
              Keys.onReturnPressed: (event) => {
                if (event.modifiers & Qt.ShiftModifier) {
                  event.accepted = false
                } else {
                  event.accepted = true
                  var newText = text
                  var id = itemObj ? itemObj.id : ""
                  var isNote = isNoteItem
                  root.editingId = ""
                  if (newText.trim() !== "") {
                    Qt.callLater(function() {
                      if (isNote) root.updateNote(id, newText)
                      else root.updateTask(id, newText)
                    })
                  }
                }
              }
              Keys.onEnterPressed: (event) => Keys.onReturnPressed(event)
              Keys.onEscapePressed: root.editingId = ""
              onVisibleChanged: {
                if (visible) {
                  forceActiveFocus()
                  cursorPosition = text.length
                }
              }
            }

            // Time Badge (Tasks only) - Placed before the action buttons
            Rectangle {
              visible: !isNoteItem
              height: Style.space(20)
              radius: Style.space(4)
              color: isTaskRunning ? Style.tint(Color.green, 0.18) : (itemStatus === "in_progress" ? Style.tint(Color.yellow, 0.15) : Style.tint(root.foreground, 0.05))
              border.color: isTaskRunning ? Color.green : (itemStatus === "in_progress" ? Color.yellow : Style.tint(root.foreground, 0.15))
              border.width: 1
              Layout.preferredWidth: timeText.implicitWidth + Style.space(10)
              Layout.alignment: Qt.AlignVCenter

              Text {
                id: timeText
                anchors.centerIn: parent
                text: itemStatus === "in_progress"
                  ? (isTaskRunning ? "⏱ " : "⏸ ") + root.formatSeconds(liveDuration)
                  : (itemStatus === "done"
                    ? root.formatDoneBadge(itemObj, root.now)
                    : root.formatCreationTime(itemObj ? itemObj.createdAt : null, root.now))
                color: isTaskRunning ? Color.green : (itemStatus === "in_progress" ? Color.yellow : Style.tint(root.foreground, 0.75))
                font.family: root.fontFamily
                font.pixelSize: Style.font.micro
                font.bold: isTaskRunning || itemStatus === "done"
              }
            }

            // In-Progress Quick Checkmark to complete task (Always visible in progress tab)
            Rectangle {
              width: Style.space(22)
              height: Style.space(22)
              radius: Style.space(5)
              color: completeMouse.containsMouse ? Style.tint(Color.green, 0.25) : Style.tint(Color.green, 0.15)
              border.color: Color.green
              border.width: 1
              visible: !isNoteItem && itemStatus === "in_progress"
              Layout.alignment: Qt.AlignVCenter

              Text {
                anchors.centerIn: parent
                text: "✓"
                color: Color.green
                font.family: root.fontFamily
                font.bold: true
                font.pixelSize: Style.font.small
              }

              MouseArea {
                id: completeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.moveTask(itemObj ? itemObj.id : "", "done")
              }
            }

            // Edit / Save Icon
            Rectangle {
              width: Style.space(24)
              height: Style.space(24)
              radius: Style.space(5)
              visible: isHovered || root.editingId === (itemObj ? itemObj.id : "")
              color: editMouse.containsMouse ? (root.editingId === (itemObj ? itemObj.id : "") ? Style.tint(Color.green, 0.2) : Style.tint(root.foreground, 0.12)) : (root.editingId === (itemObj ? itemObj.id : "") ? Style.tint(Color.green, 0.1) : Style.tint(root.foreground, 0.06))
              border.color: editMouse.containsMouse ? (root.editingId === (itemObj ? itemObj.id : "") ? Color.green : Style.tint(root.foreground, 0.3)) : (root.editingId === (itemObj ? itemObj.id : "") ? Style.tint(Color.green, 0.6) : Style.tint(root.foreground, 0.15))
              border.width: 1
              Layout.alignment: isNoteItem ? Qt.AlignTop : Qt.AlignVCenter
              Layout.topMargin: isNoteItem ? Style.space(2) : 0

              Text {
                anchors.centerIn: parent
                text: root.editingId === (itemObj ? itemObj.id : "") ? "✓" : "󰏫"
                color: root.editingId === (itemObj ? itemObj.id : "") ? Color.green : Style.tint(root.foreground, 0.85)
                font.family: root.fontFamily
                font.pixelSize: root.editingId === (itemObj ? itemObj.id : "") ? Style.font.small : Style.font.micro
                font.bold: root.editingId === (itemObj ? itemObj.id : "")
              }

              MouseArea {
                id: editMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.editingId === (itemObj ? itemObj.id : "")) {
                    var newText = editField.text
                    var id = itemObj ? itemObj.id : ""
                    var isNote = isNoteItem
                    root.editingId = ""
                    if (newText.trim() !== "") {
                      Qt.callLater(function() {
                        if (isNote) root.updateNote(id, newText)
                        else root.updateTask(id, newText)
                      })
                    }
                  } else {
                    root.editingId = itemObj ? itemObj.id : ""
                  }
                }
              }
            }

            // Copy Icon
            Rectangle {
              width: Style.space(24)
              height: Style.space(24)
              radius: Style.space(5)
              visible: isNoteItem && (isHovered || isItemFeedback)
              color: isItemFeedback ? Style.tint(Color.green, 0.18) : (copyMouse.containsMouse ? Style.tint(root.foreground, 0.12) : Style.tint(root.foreground, 0.06))
              border.color: isItemFeedback ? Color.green : (copyMouse.containsMouse ? Style.tint(root.foreground, 0.3) : Style.tint(root.foreground, 0.15))
              border.width: 1
              Layout.alignment: isNoteItem ? Qt.AlignTop : Qt.AlignVCenter
              Layout.topMargin: isNoteItem ? Style.space(2) : 0

              Text {
                id: copyLabel
                anchors.centerIn: parent
                text: isItemFeedback ? "✓" : "󰆏"
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
                onClicked: root.copyToClipboard(itemObj ? (itemObj.text || itemObj.title) : "", itemObj ? itemObj.id : "")
              }
            }

            // Delete Button (Hover)
            Rectangle {
              width: Style.space(24)
              height: Style.space(24)
              radius: Style.space(5)
              visible: isHovered
              color: deleteMouse.containsMouse ? Style.tint(Color.red, 0.15) : Style.tint(root.foreground, 0.06)
              border.color: deleteMouse.containsMouse ? Color.red : Style.tint(root.foreground, 0.15)
              border.width: 1
              Layout.alignment: isNoteItem ? Qt.AlignTop : Qt.AlignVCenter
              Layout.topMargin: isNoteItem ? Style.space(2) : 0

              Text {
                anchors.centerIn: parent
                text: "✕"
                color: deleteMouse.containsMouse ? Color.red : Style.tint(root.foreground, 0.8)
                font.family: root.fontFamily
                font.pixelSize: Style.font.small
                font.bold: true
              }

              MouseArea {
                id: deleteMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (isNoteItem) {
                    root.deleteNote(itemObj ? itemObj.id : "")
                  } else {
                    root.deleteTask(itemObj ? itemObj.id : "")
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
