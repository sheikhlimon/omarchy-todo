import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "limon.todo"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool hasRunningTask: panelLoader.item ? panelLoader.item.hasRunningTask : false
  readonly property string activeTimerText: panelLoader.item ? panelLoader.item.activeTimerText : ""

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("host" in target) target.host = root
  }

  function open() {
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf0ae"
    useActiveColor: false
    tooltipText: root.hasRunningTask ? "Tasks (Active: " + root.activeTimerText + ")" : "Tasks & Time Tracker"
    onPressed: root.toggle()
  }
}
