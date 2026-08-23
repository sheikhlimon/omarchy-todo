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
  readonly property string activeTimerText: runningTask ? (runningTask.title || "") : ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Color.muted
  readonly property color bg: Color.popups.background
  readonly property color borderCol: Color.popups.border
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool isLightMode: (bg.r * 0.299 + bg.g * 0.587 + bg.b * 0.114) > 0.5
  readonly property color cardBackground: isLightMode ? "#FFFFFF" : Util.alpha(foreground, 0.05)

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
    root.dataVersion++
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
    var list = JSON.parse(JSON.stringify(root.allNotes || []))
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        list[i].text = text.trim()
        break
      }
    }
    root.allNotes = list
    root.dataVersion++
    saveTasks()
  }

  function updateTask(id, title) {
    if (!title || title.trim() === "") return
    var list = JSON.parse(JSON.stringify(root.allTasks || []))
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        list[i].title = title.trim()
        break
      }
    }
    root.allTasks = list
    root.dataVersion++
    saveTasks()
  }

  function toggleNoteDone(id) {
    var list = JSON.parse(JSON.stringify(root.allNotes || []))
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        list[i].done = !list[i].done
        break
      }
    }
    root.allNotes = list
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
      if (newStatus === "todo") {
        task.timeSpentSeconds = 0
        task.timer = null
      }
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
    return "✓ " + spent
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
          root.dataVersion++;
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
    var _ = root.dataVersion
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
    focusTarget: keyCatcher
    contentWidth: popupPanel.fittedContentWidth(Style.space(380))
    contentHeight: popupPanel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          // ---------- Tab switch (Matching Omanews 1:1) ----------
          Row {
            id: tabSwitch
            width: parent.width
            spacing: Style.space(4)

            readonly property var tabDefs: [
              { id: "todo", name: "To-Do" },
              { id: "in_progress", name: "Progress" },
              { id: "done", name: "Done" },
              { id: "notes", name: "Notes" }
            ]
            readonly property real cellWidth: (width - spacing * (tabDefs.length - 1)) / tabDefs.length

            Repeater {
              model: tabSwitch.tabDefs

              Button {
                required property var modelData
                required property int index

                width: tabSwitch.cellWidth
                text: {
                  var _ = root.dataVersion
                  var count = 0
                  if (modelData.id === "notes") {
                    count = (root.allNotes || []).length
                  } else {
                    count = (root.allTasks || []).filter(t => t.status === modelData.id).length
                  }
                  return modelData.name + " (" + count + ")"
                }
                selected: modelData.id === root.activeTab
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.activeTab = modelData.id
              }
            }
          }

          // ---------- Quick-Add Input ----------
          Rectangle {
            width: parent.width
            implicitHeight: Math.min(Style.space(120), Math.max(Style.space(38), itemInput.contentHeight + Style.space(16)))
            radius: Style.cornerRadius
            color: "transparent"
            border.color: itemInput.activeFocus ? Color.accent : Util.alpha(root.foreground, 0.15)
            border.width: itemInput.activeFocus ? 1.5 : 1

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(8)

              Text {
                Layout.alignment: Qt.AlignVCenter
                text: "+"
                color: itemInput.activeFocus ? Color.accent : Util.alpha(root.foreground, 0.5)
                font.family: root.fontFamily
                font.bold: true
                font.pixelSize: Style.font.subtitle
              }

              QQC.ScrollView {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumHeight: Style.space(100)
                QQC.ScrollBar.vertical.policy: QQC.ScrollBar.AsNeeded
                clip: true

                QQC.TextArea {
                  id: itemInput
                  wrapMode: Text.Wrap
                  verticalAlignment: Text.AlignVCenter
                  placeholderText: root.activeTab === "notes" ? "Add new note..." : "Add new task..."
                  placeholderTextColor: Util.alpha(root.foreground, 0.4)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.bold: true
                  font.pixelSize: Style.font.subtitle
                  background: null
                  leftPadding: 0
                  rightPadding: 0
                  topPadding: Style.space(6)
                  bottomPadding: Style.space(6)
                  Keys.onReturnPressed: (event) => {
                    if (event.modifiers & Qt.ShiftModifier) {
                      event.accepted = false
                    } else {
                      event.accepted = true
                      var t = text
                      text = ""
                      if (root.activeTab === "notes") {
                        root.addNote(t)
                      } else {
                        root.addTask(t)
                      }
                    }
                  }
                  Keys.onEnterPressed: (event) => Keys.onReturnPressed(event)
                  Keys.onEscapePressed: root.close()
                }
              }
            }
          }



          // ---------- Empty State ----------
          Text {
            visible: root.currentItemsList.length === 0
            width: parent.width
            topPadding: Style.space(24)
            bottomPadding: Style.space(24)
            text: root.activeTab === "notes" ? "No notes yet.\nType above to add one." : "No tasks here.\nType above to add one."
            color: Util.alpha(root.foreground, 0.75)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---------- Card List ----------
          Repeater {
            model: root.currentItemsList

            Rectangle {
              id: itemCard
              required property var modelData
              required property int index
              width: column.width
              implicitHeight: Math.max(Style.space(42), itemRow.implicitHeight + Style.space(12))
              height: implicitHeight
              radius: Style.cornerRadius

              property var itemObj: { var _ = root.dataVersion; return modelData }
              property string itemStatus: { var _ = root.dataVersion; return itemObj ? (itemObj.status || "") : "" }
              property bool isNoteItem: root.activeTab === "notes"
              property bool isEditingThis: root.editingId === (itemObj ? itemObj.id : "")
              property bool isTaskRunning: { var _ = root.dataVersion; return !isNoteItem && itemObj && itemObj.timer && itemObj.timer.isRunning === true }
              property int liveDuration: { var _ = root.dataVersion; return isNoteItem ? 0 : root.getLiveTime(itemObj, root.now) }
              property bool isHovered: cardHover.hovered
              property bool isItemFeedback: root.feedbackTaskId === (itemObj ? itemObj.id : "")

              color: isTaskRunning
                ? Util.alpha(Color.accent, 0.08)
                : root.cardBackground
              border.color: isTaskRunning ? Color.accent : (isEditingThis ? Color.accent : (isHovered ? Util.alpha(root.foreground, 0.25) : Util.alpha(root.foreground, 0.12)))
              border.width: 1

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
                  color: itemStatus === "done"
                    ? Util.alpha(Color.accent, 0.12)
                    : (isTaskRunning ? Color.accent : (leftBtnMouse.containsMouse ? Util.alpha(root.foreground, 0.12) : Util.alpha(root.foreground, 0.05)))
                  border.color: itemStatus === "done" ? Color.accent : (isTaskRunning ? Color.accent : (leftBtnMouse.containsMouse ? Util.alpha(root.foreground, 0.3) : Util.alpha(root.foreground, 0.15)))
                  border.width: 1

                  Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: text === "󰐊" ? 1 : 0
                    text: itemStatus === "done" ? "↺" : (isTaskRunning ? "󰏤" : "󰐊")
                    color: itemStatus === "done" ? Color.accent : (isTaskRunning ? Color.popups.background : root.foreground)
                    font.family: root.fontFamily
                    font.bold: true
                    font.pixelSize: Style.font.bodySmall
                  }

                  MouseArea {
                    id: leftBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
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
                  visible: !isEditingThis
                  Layout.fillWidth: true
                  Layout.alignment: isNoteItem ? Qt.AlignTop : Qt.AlignVCenter
                  wrapMode: Text.Wrap
                  text: { var _ = root.dataVersion; return isNoteItem ? (itemObj.text || "") : (itemObj.title || "") }
                  textFormat: isNoteItem ? Text.MarkdownText : Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.bold: true
                  font.pixelSize: Style.font.subtitle
                }

                QQC.TextArea {
                  id: editField
                  visible: isEditingThis
                  Layout.fillWidth: true
                  Layout.alignment: isNoteItem ? Qt.AlignTop : Qt.AlignVCenter
                  wrapMode: Text.Wrap
                  text: { var _ = root.dataVersion; return isNoteItem ? (itemObj ? (itemObj.text || "") : "") : (itemObj ? (itemObj.title || "") : "") }
                  color: root.foreground
                  font.family: root.fontFamily
                  font.bold: true
                  font.pixelSize: Style.font.subtitle
                  background: Rectangle {
                    color: "transparent"
                    radius: Style.space(4)
                    border.color: Color.accent
                    border.width: 1.5
                  }
                  leftPadding: Style.space(6)
                  rightPadding: Style.space(6)
                  topPadding: Style.space(4)
                  bottomPadding: Style.space(4)
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
                        if (isNote) root.updateNote(id, newText)
                        else root.updateTask(id, newText)
                      } else {
                        text = isNoteItem ? (itemObj ? (itemObj.text || "") : "") : (itemObj ? (itemObj.title || "") : "")
                      }
                    }
                  }
                  Keys.onEnterPressed: (event) => Keys.onReturnPressed(event)
                  Keys.onEscapePressed: {
                    text = isNoteItem ? (itemObj ? (itemObj.text || "") : "") : (itemObj ? (itemObj.title || "") : "")
                    root.editingId = ""
                  }
                  onVisibleChanged: {
                    if (visible) {
                      text = isNoteItem ? (itemObj ? (itemObj.text || "") : "") : (itemObj ? (itemObj.title || "") : "")
                      forceActiveFocus()
                      cursorPosition = text.length
                    }
                  }
                }

                // Time Badge (Tasks only)
                Rectangle {
                  visible: !isNoteItem && !isEditingThis
                  height: (itemStatus === "in_progress") ? Style.space(22) : Style.space(20)
                  radius: Style.space(4)
                  color: isTaskRunning ? Util.alpha(Color.accent, 0.15) : "transparent"
                  border.color: isTaskRunning ? Color.accent : Util.alpha(root.foreground, 0.15)
                  border.width: 1
                  Layout.preferredWidth: timeText.implicitWidth + ((itemStatus === "in_progress") ? Style.space(12) : Style.space(10))
                  Layout.alignment: Qt.AlignVCenter

                  Text {
                    id: timeText
                    anchors.centerIn: parent
                    text: itemStatus === "in_progress"
                      ? (isTaskRunning ? "󰔟 " : "󰏤 ") + root.formatSeconds(liveDuration)
                      : (itemStatus === "done"
                        ? root.formatDoneBadge(itemObj, root.now)
                        : root.formatCreationTime(itemObj ? itemObj.createdAt : null, root.now))
                    color: isTaskRunning ? Color.accent : Util.alpha(root.foreground, 0.70)
                    font.family: root.fontFamily
                    font.pixelSize: (itemStatus === "in_progress") ? Style.font.body : Style.font.bodySmall
                    font.bold: (itemStatus === "in_progress")
                  }
                }

                // In-Progress Quick Checkmark
                Rectangle {
                  width: Style.space(24)
                  height: Style.space(24)
                  radius: Style.space(5)
                  color: completeMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                  border.color: completeMouse.containsMouse ? Color.accent : Util.alpha(root.foreground, 0.25)
                  border.width: 1
                  visible: !isNoteItem && itemStatus === "in_progress" && !isEditingThis
                  Layout.alignment: Qt.AlignVCenter

                  Text {
                    anchors.centerIn: parent
                    text: "✓"
                    color: completeMouse.containsMouse ? Color.accent : Util.alpha(root.foreground, 0.70)
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

                // Edit Start Button (󰏫)
                Rectangle {
                  width: Style.space(24)
                  height: Style.space(24)
                  radius: Style.space(5)
                  visible: !isEditingThis && isHovered
                  color: editStartMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                  border.color: editStartMouse.containsMouse ? Util.alpha(root.foreground, 0.25) : "transparent"
                  border.width: 1
                  Layout.alignment: isNoteItem ? Qt.AlignTop : Qt.AlignVCenter
                  Layout.topMargin: isNoteItem ? Style.space(2) : 0

                  Text {
                    anchors.centerIn: parent
                    text: "󰏫"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.micro
                  }

                  MouseArea {
                    id: editStartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.editingId = itemObj ? itemObj.id : ""
                  }
                }

                // Edit Confirm Checkmark Button
                Rectangle {
                  width: Style.space(24)
                  height: Style.space(24)
                  radius: Style.space(5)
                  visible: isEditingThis
                  color: editSaveMouse.containsMouse ? Style.hoverFillFor(Color.accent, Color.accent) : "transparent"
                  border.color: editSaveMouse.containsMouse ? Color.accent : Util.alpha(Color.accent, 0.4)
                  border.width: 1
                  Layout.alignment: isNoteItem ? Qt.AlignTop : Qt.AlignVCenter
                  Layout.topMargin: isNoteItem ? Style.space(2) : 0

                  Text {
                    anchors.centerIn: parent
                    text: "✓"
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.small
                    font.bold: true
                  }

                  MouseArea {
                    id: editSaveMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      var newText = editField.text
                      var id = itemObj ? itemObj.id : ""
                      var isNote = isNoteItem
                      root.editingId = ""
                      if (newText.trim() !== "") {
                        if (isNote) root.updateNote(id, newText)
                        else root.updateTask(id, newText)
                      } else {
                        editField.text = isNoteItem ? (itemObj ? (itemObj.text || "") : "") : (itemObj ? (itemObj.title || "") : "")
                      }
                    }
                  }
                }

                // Edit Cancel Cross Button
                Rectangle {
                  width: Style.space(24)
                  height: Style.space(24)
                  radius: Style.space(5)
                  visible: isEditingThis
                  color: editCancelMouse.containsMouse ? Style.hoverFillFor(Color.urgent, Color.urgent) : "transparent"
                  border.color: editCancelMouse.containsMouse ? Color.urgent : Util.alpha(Color.urgent, 0.4)
                  border.width: 1
                  Layout.alignment: isNoteItem ? Qt.AlignTop : Qt.AlignVCenter
                  Layout.topMargin: isNoteItem ? Style.space(2) : 0

                  Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: Color.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.small
                  }

                  MouseArea {
                    id: editCancelMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      editField.text = isNoteItem ? (itemObj ? (itemObj.text || "") : "") : (itemObj ? (itemObj.title || "") : "")
                      root.editingId = ""
                    }
                  }
                }

                // Copy Icon (Notes ONLY)
                Rectangle {
                  width: Style.space(24)
                  height: Style.space(24)
                  radius: Style.space(5)
                  visible: isNoteItem && !isEditingThis && (cardHover.hovered || isItemFeedback)
                  color: isItemFeedback ? Color.accent : (copyMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
                  border.color: isItemFeedback ? Color.accent : (copyMouse.containsMouse ? Util.alpha(root.foreground, 0.25) : "transparent")
                  border.width: 1
                  Layout.alignment: isNoteItem ? Qt.AlignTop : Qt.AlignVCenter
                  Layout.topMargin: isNoteItem ? Style.space(2) : 0

                  Text {
                    id: copyLabel
                    anchors.centerIn: parent
                    text: isItemFeedback ? "✓" : "󰆏"
                    color: isItemFeedback ? Color.popups.background : root.foreground
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



                // Delete Button
                Rectangle {
                  width: Style.space(24)
                  height: Style.space(24)
                  radius: Style.space(5)
                  visible: !isEditingThis && isHovered
                  color: deleteMouse.containsMouse ? Style.hoverFillFor(Color.urgent, Color.urgent) : "transparent"
                  border.color: deleteMouse.containsMouse ? Color.urgent : "transparent"
                  border.width: 1
                  Layout.alignment: isNoteItem ? Qt.AlignTop : Qt.AlignVCenter
                  Layout.topMargin: isNoteItem ? Style.space(2) : 0

                  Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: deleteMouse.containsMouse ? Color.urgent : root.foreground
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
          }
        }
      }
    }
  }
}
