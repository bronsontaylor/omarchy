import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "DockModel.js" as DockModel

// One screen's dock. It stays mapped and only hides its contents, so switching
// to a floating workspace does not wait on a fresh layer surface. While hidden the
// mask is empty and clicks fall through to the windows below.
PanelWindow {
  id: window
  // Right-to-left languages read this window mirrored.
  Binding { target: window.contentItem; property: "LayoutMirroring.enabled"; value: Commons.I18n.rightToLeft }
  Binding { target: window.contentItem; property: "LayoutMirroring.childrenInherit"; value: true }


  property var dock: null

  readonly property string requestedPosition: dock ? dock.position : "bottom"
  property string position: "bottom"
  readonly property bool vertical: position === "left" || position === "right"
  property bool positionReady: false
  property bool positionChanging: false
  property real positionSlide: 0
  readonly property real positionTravel: window.slotSize + window.iconSize + window.gap + (window.vertical ? body.width : body.height)
  readonly property real positionSlideX: positionSlide * (position === "left" ? -positionTravel : position === "right" ? positionTravel : 0)
  readonly property real positionSlideY: positionSlide * (position === "top" ? -positionTravel : position === "bottom" ? positionTravel : 0)
  onRequestedPositionChanged: {
    if (!positionReady) { position = requestedPosition; return }
    if (!shown) {
      positionMove.stop(); positionChanging = false; positionSlide = 0
      position = requestedPosition
      return
    }
    if (requestedPosition === position && !positionChanging) return
    closeMenu()
    positionChanging = true
    positionMove.restart()
  }
  SequentialAnimation {
    id: positionMove
    NumberAnimation { target: window; property: "positionSlide"; to: 1; duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    ScriptAction { script: window.position = window.requestedPosition }
    PauseAnimation { duration: Style.duration(80) }
    NumberAnimation { target: window; property: "positionSlide"; to: 0; duration: Style.duration(240); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    ScriptAction {
      script: {
        window.hoverStale = true
        window.dropPoint = bodyHover.point.position
        window.positionChanging = false
      }
    }
  }
  readonly property var monitor: Hyprland.monitorFor(screen)
  readonly property var workspace: monitor ? monitor.activeWorkspace : null
  readonly property int workspaceId: dock ? dock.workspaceNumber(workspace) : -1
  // The most fullscreen window on the workspace, as Hyprland counts it: 1 is
  // maximized, and 2 or 3 fullscreen.
  readonly property int fullscreenMode: {
    var mode = 0
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i]
      if (!toplevel.workspace || window.dock.workspaceNumber(toplevel.workspace) !== workspaceId) continue
      var ipc = toplevel.lastIpcObject
      mode = Math.max(mode, ipc && ipc.fullscreen ? ipc.fullscreen : 0)
    }
    return mode
  }
  readonly property bool shown: !!dock && dock.isFloating(workspaceId) && fullscreenMode < 2
  // Fullscreen hides the dock; maximized windows reveal it at the screen edge.
  readonly property bool autohide: !!dock && (dock.autohide || fullscreenMode === 1)
  property bool revealed: false
  readonly property bool menuOpen: menuItem !== null || settingsMenu
  readonly property bool tucked: autohide && !(revealed || menuOpen || dragging || insertIndex >= 0)
  readonly property bool contentShown: shown && !tucked

  readonly property int gap: Style.spacing.xs
  readonly property real targetIconSize: (window.dock ? window.dock.iconSize : 36) * Style.fontScale
  property real iconSize: targetIconSize
  Behavior on iconSize {
    enabled: window.shown && !window.positionChanging
    NumberAnimation { id: iconResize; duration: Style.duration(180); easing.type: Easing.OutCubic }
  }
  // Each app has a square slot with its icon in the middle, and the slots run
  // straight to the edge of the dock.
  readonly property int iconInset: Style.spacing.md
  readonly property real slotSize: iconSize + iconInset * 2
  // Room inward of the dock for its menus: the tallest, the apps button's,
  // has five rows.
  // A fixed cross-axis surface avoids Wayland configure churn while resizing.
  readonly property real maximumIconSize: 64 * Style.fontScale
  readonly property real maximumSlotSize: maximumIconSize + iconInset * 2
  readonly property real maximumShelfPadding: Math.max(Style.space(12), maximumIconSize * 0.5 - iconInset + Style.space(6))
  readonly property int popupRoom: Style.spacing.popupRowHeight * 7 + Style.spacing.sm * 2 + Style.normalBorderWidth * 2 + gap * 2
  // Icons pop away from the screen edge.
  readonly property int popOrigin: position === "top" ? Item.Top
    : position === "left" ? Item.Left
    : position === "right" ? Item.Right
    : Item.Bottom

  // The app being dragged along the dock, how far the pointer has taken it,
  // and the slot it would land in.
  property int dragIndex: -1
  property int dropIndex: -1
  property real dragOffset: 0
  readonly property bool dragging: dragIndex >= 0
  // Off while a drop resets the slots: they snap to where the reorder puts
  // them rather than sliding back from where they stepped aside. Set before
  // the drag state changes, so the slots never see the reset animated.
  property bool animateShifts: true
  // After a drop the slots have moved under a pointer that has not, so what
  // they think is hovered is stale until it moves again.
  property bool hoverStale: false
  property point dropPoint
  // Where an app dragged in from the app grid would land, or -1.
  property int insertIndex: -1

  // Where this window sits on its screen, which a point from the app grid's
  // fullscreen surface is given in: against its edge, clear of the space
  // other surfaces such as the bar reserve. Hyprland lists that space as
  // left, top, right, bottom.
  function origin() {
    var reserved = monitor && monitor.lastIpcObject && monitor.lastIpcObject.reserved ? monitor.lastIpcObject.reserved : [0, 0, 0, 0]
    var left = reserved[0] || 0, top = reserved[1] || 0, right = reserved[2] || 0, bottom = reserved[3] || 0
    var x = window.position === "right" ? screen.width - right - window.width : left
    var y = window.position === "bottom" ? screen.height - bottom - window.height : top
    return Qt.point(x, y)
  }

  // An app from the app grid lands where the pointer is, once it is over the
  // dock or close to it on the inward side.
  function moveExternalDrag(screenX, screenY) {
    var at = window.origin()
    var point = Qt.point(screenX - at.x - body.x, screenY - at.y - body.y)
    var reach = window.slotSize
    var along = window.vertical ? point.y : point.x
    var across = window.vertical ? point.x : point.y
    var length = window.vertical ? body.height : body.width
    var depth = window.vertical ? body.width : body.height
    var near = along >= -window.slotSize && along <= length + window.slotSize && across >= -reach && across <= depth + reach
    if (window.shown && window.autohide && near) window.revealed = true
    window.insertIndex = window.shown && near ? window.slotIndexAt(point) : -1
  }

  function dropExternalDrag(screenX, screenY, key) {
    window.moveExternalDrag(screenX, screenY)
    window.settleShifts()
    if (window.insertIndex >= 0 && key && window.dock) window.dock.pinAt(key, window.insertIndex)
    window.endExternalDrag()
  }

  function endExternalDrag() {
    window.insertIndex = -1
    if (window.autohide) hideTimer.restart()
  }

  // The slot a point along the dock falls before, counting from the first app.
  function slotIndexAt(point) {
    var along = (window.vertical ? point.y : point.x) - body.panelPadding
    var count = appRepeater.count
    for (var i = 0; i < count; i++) {
      var slot = appRepeater.itemAt(i)
      if (!slot) continue
      var start = (window.vertical ? slot.y : slot.x) + slot.sectionGap
      var size = window.vertical ? slot.height : slot.width
      if (along < start + size / 2) return i
    }
    return count
  }
  property var menuItem: null
  property Item menuSlot: null
  property point menuPoint: Qt.point(0, 0)
  // The apps button's menu: where the dock sits and whether it hides.
  property bool settingsMenu: false

  onWorkspaceIdChanged: if (dock) dock.readMode(workspaceId)
  onShownChanged: {
    if (shown) return
    closeMenu()
    window.revealed = false
  }
  Component.onCompleted: {
    position = requestedPosition
    positionReady = true
    if (dock) dock.readMode(workspaceId)
  }

  function setMenuPoint(slot, x, y) {
    window.menuPoint = slot.mapToItem(window.contentItem,
      x === undefined ? slot.width / 2 : x,
      y === undefined ? slot.height / 2 : y)
  }

  function openMenu(item, slot, x, y) {
    window.setMenuPoint(slot)
    window.settingsMenu = false
    window.menuItem = item
    window.menuSlot = slot
  }

  function openSettingsMenu(slot, x, y) {
    if (slot === body) window.setMenuPoint(slot, x, y)
    else window.setMenuPoint(slot)
    window.menuItem = null
    window.settingsMenu = true
    window.menuSlot = slot
  }

  function settleShifts() {
    window.animateShifts = false
    Qt.callLater(function() { window.animateShifts = true })
  }

  function endDrag() {
    window.settleShifts()
    window.hoverStale = true
    window.dragIndex = -1
    window.dropIndex = -1
    window.dragOffset = 0
  }

  function closeMenu() {
    window.menuItem = null
    window.settingsMenu = false
    window.menuSlot = null
    if (window.autohide) hideTimer.restart()
  }

  // Place the menu inward of the dock at the actual click, including gaps.
  function popupX(slot, popup) {
    if (!slot) return 0
    var center = window.menuPoint.x
    if (window.position === "left") return body.x + body.width + window.gap
    if (window.position === "right") return body.x - window.gap - popup.width
    return Math.max(window.gap, Math.min(window.width - popup.width - window.gap, center - popup.width / 2))
  }

  function popupY(slot, popup) {
    if (!slot) return 0
    var center = window.menuPoint.y
    if (window.position === "top") return body.y + body.height + window.gap
    if (window.position === "bottom") return body.y - window.gap - popup.height
    return Math.max(window.gap, Math.min(window.height - popup.height - window.gap, center - popup.height / 2))
  }

  visible: true
  color: "transparent"
  WlrLayershell.namespace: "omarchy-dock"
  // Stay above app windows; newly opened taskbar overlays stay above the dock.
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  // Kept clear of the bar's reserved edge, without reserving one of its own:
  // floating windows go where they are put.
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0

  anchors {
    top: window.position !== "bottom"
    bottom: window.position !== "top"
    left: window.position !== "right"
    right: window.position !== "left"
  }

  implicitWidth: window.vertical ? window.gap + window.maximumSlotSize + window.maximumShelfPadding * 2 + window.popupRoom : 0
  implicitHeight: window.vertical ? 0 : window.gap + window.maximumSlotSize + window.maximumShelfPadding * 2 + window.popupRoom

  PopupExclusion {
    screen: window.screen ? window.screen.name : ""
    enabled: window.shown && !window.positionChanging
    target: window.contentShown ? body : edgeTrigger
    reference: window.contentItem
    offset: window.origin()
  }
  PopupExclusion {
    screen: window.screen ? window.screen.name : ""
    enabled: menu.visible
    target: menu
    reference: window.contentItem
    offset: window.origin()
  }

  mask: Region {
    item: window.contentShown && !window.positionChanging ? body : null

    Region { item: window.shown && window.autohide && !window.positionChanging ? edgeTrigger : null }
    Region { item: menu.visible ? menu : null }
  }

  onAutohideChanged: window.revealed = false

  Timer {
    id: hideTimer
    // Long enough to cross a gap between the edge and the icons, no longer.
    interval: 150
    onTriggered: {
      if (!bodyHover.hovered && !edgeHover.hovered && !window.menuOpen && !window.dragging) window.revealed = false
    }
  }

  // The strip along the screen edge that brings an auto-hidden dock back.
  Item {
    id: edgeTrigger

    readonly property int depth: window.gap + Style.spacing.xxs

    x: window.position === "left" ? 0 : window.position === "right" ? window.width - depth : body.x
    y: window.position === "top" ? 0 : window.position === "bottom" ? window.height - depth : body.y
    width: window.vertical ? depth : body.width
    height: window.vertical ? body.height : depth

    HoverHandler {
      id: edgeHover
      onHoveredChanged: {
        if (hovered) window.revealed = true
        else hideTimer.restart()
      }
    }
  }

  HyprlandFocusGrab {
    active: window.menuOpen
    windows: [window]
    onCleared: window.closeMenu()
  }

  Item {
    id: body
    transform: Translate { x: window.positionSlideX; y: window.positionSlideY }

    // The strip keeps its order in every language, like the bar: drags and
    // drops reckon slots along x from the first app. Only the menu mirrors.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    // Reserve breathing room for the panel and the largest hover growth.
    readonly property real shelfPadding: Math.max(Style.space(12), window.iconSize * (window.dock ? window.dock.magnification : 0) - window.iconInset + Style.space(6))
    property real panelPadding: (window.dock && window.dock.shelf) ? shelfPadding : 0
    Behavior on panelPadding {
      enabled: window.shown && !window.positionChanging && !iconResize.running
      NumberAnimation { duration: Style.duration(240); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }
    readonly property bool hasWindowGroup: !!window.dock && window.dock.items.some(function(item) { return item.windows.length > 0 })
    width: panelPadding * 2 + slots.implicitWidth + (!window.vertical && hasWindowGroup && (window.dock && window.dock.instances) ? Style.space(40) : 0)
    height: panelPadding * 2 + slots.implicitHeight + (window.vertical && hasWindowGroup && (window.dock && window.dock.instances) ? Style.space(40) : 0)
    // How far the dock is tucked past its edge. Auto-hide slides it, but only
    // while the dock is on screen: arriving on a floating workspace shows it
    // where it belongs at once.
    property real tuck: window.tucked ? window.slotSize + shelfPadding * 2 + window.gap : 0

    // Tucking away is quicker than coming back. A gentler curve than
    // Style.easeOut, which crosses the short slide in a frame or two.
    Behavior on tuck {
      id: tuckMotion
      enabled: window.shown && !window.positionChanging
      NumberAnimation {
        duration: Style.duration(tuckMotion.targetValue > 0 ? 160 : 240)
        easing.type: Easing.OutCubic
      }
    }

    x: window.position === "left" ? window.gap - tuck
      : window.position === "right" ? window.width - width - window.gap + tuck
      : (window.width - width) / 2
    y: window.position === "top" ? window.gap - tuck
      : window.position === "bottom" ? window.height - height - window.gap + tuck
      : (window.height - height) / 2
    // Switching between tiled and floating workspaces shows and hides the dock
    // at once, with nothing to watch in between. Hidden by opacity rather than
    // visibility, so the icons keep their textures and are drawn on the first
    // frame back instead of being uploaded again.
    opacity: window.shown ? 1 : 0

    Rectangle {
      anchors.fill: parent
      opacity: (window.dock && window.dock.shelf) ? 1 : 0
      visible: opacity > 0
      Behavior on opacity {
        enabled: window.shown && !window.positionChanging
        NumberAnimation { duration: Style.duration(240); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
      }
      radius: Style.cornerRadius
      // Theme shelf, fixed at 15% transparency (85% opacity).
      color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.85)
      border.width: Math.max(1, Style.space(1))
      border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.18)
    }

    MouseArea {
      anchors.fill: parent
      z: -1
      acceptedButtons: Qt.RightButton
      onClicked: function(event) { window.openSettingsMenu(body, event.x, event.y) }
    }

    HoverHandler {
      id: bodyHover
      onHoveredChanged: if (!hovered && window.autohide) hideTimer.restart()
      // Only a real move clears it: the release itself reports the pointer too.
      onPointChanged: {
        if (!window.hoverStale || window.dragging) return
        var at = point.position
        if (Math.hypot(at.x - window.dropPoint.x, at.y - window.dropPoint.y) > Style.space(4)) window.hoverStale = false
      }
    }

    Grid {
      id: slots
      x: body.panelPadding
      y: body.panelPadding
      columns: window.vertical ? 1 : appRepeater.count + 1
      move: Transition {
        enabled: !window.positionChanging && !iconResize.running && !window.dragging && window.animateShifts
        NumberAnimation {
          properties: "x,y"
          duration: Style.duration(250)
          easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut
        }
      }

      AppsSlot { id: launcherSlot }

      Repeater {
        id: appRepeater
        model: window.dock ? window.dock.itemModel : null

        delegate: Item {
          id: slotContainer
          required property int index
          required property string key
          readonly property var entry: window.dock ? window.dock.itemFor(key) : null
          // Keep every moving slot the same size. The separator gap belongs
          // to the whole window group, so it cannot stretch a moving group.
          readonly property int sectionGap: (window.dock && window.dock.instances) && entry && entry.windows.length > 0 ? Style.space(40) : 0
          width: window.slotSize
          height: window.slotSize
          AppSlot {
            index: slotContainer.index
            key: slotContainer.key
            x: window.vertical ? 0 : slotContainer.sectionGap
            y: window.vertical ? slotContainer.sectionGap : 0
          }
        }
      }
    }
  }

  Rectangle {
    readonly property int launcherCount: window.dock
      ? window.dock.items.filter(function(item) { return item.windows.length === 0 }).length : 0
    readonly property real boundary: body.panelPadding + (launcherCount + 1) * window.slotSize + Style.space(20)
    transform: Translate { x: window.positionSlideX; y: window.positionSlideY }
    visible: (window.dock && window.dock.instances) && window.contentShown && launcherCount > 0 && appRepeater.count > launcherCount
    width: Style.space(5)
    height: width
    radius: width / 2
    color: Commons.Color.foreground
    opacity: 0.25 // 75% transparency
    x: body.x + (window.vertical ? (body.width - width) / 2 : boundary - width / 2)
    y: body.y + (window.vertical ? boundary - height / 2 : (body.height - height) / 2)
  }

  component Slot: Item {
    id: slot

    // Only the dragged icon is lifted while a drag is on; none of the others
    // pop as it passes over them.
    property bool hovered: mouse.containsMouse && !window.hoverStale && !window.dragging
    property bool pressed: mouse.pressed
    property alias mouse: mouse

    // Use the pointer's distance along the strip for a continuous wave:
    // the closest icon grows most, with a smaller lift for its neighbors.
    readonly property real pointerInfluence: {
      if (!window.dock || window.dock.magnification === 0) return slot.hovered ? 1 : 0
      if (window.positionChanging || !bodyHover.hovered || window.hoverStale || window.dragging
          || window.insertIndex >= 0 || !window.contentShown) return 0
      var pointer = bodyHover.point.position
      var center = slot.mapToItem(body, slot.width / 2, slot.height / 2)
      var distance = Math.abs(window.vertical ? pointer.y - center.y : pointer.x - center.x)
      var reach = window.slotSize * 2
      return distance < reach ? (1 + Math.cos(Math.PI * distance / reach)) / 2 : 0
    }
    readonly property real magnification: 1 + (window.dock ? window.dock.magnification : 0) * pointerInfluence

    width: window.slotSize
    height: window.slotSize

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    }
  }

  component AppsSlot: Slot {
    id: appsSlot

    property real displayedShift: window.insertIndex >= 0 ? -window.slotSize / 2 : 0

    Behavior on displayedShift {
      enabled: !window.positionChanging && window.animateShifts
      NumberAnimation { duration: Style.duration(150); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    transform: Translate {
      x: window.vertical ? 0 : appsSlot.displayedShift
      y: window.vertical ? appsSlot.displayedShift : 0
    }

    mouse.onClicked: function(event) {
      if (event.button === Qt.RightButton) {
        window.openSettingsMenu(appsSlot, event.x, event.y)
        return
      }
      window.closeMenu()
      if (window.dock) window.dock.openApps()
    }

    // A grid of app squares reads as "all apps" in any icon theme. Drawn
    // rather than taken from a font, so its edges stay crisp on the
    // transparent dock and it fills its slot like the app icons beside it.
    Item {
      x: window.iconInset
      y: window.iconInset
      width: window.iconSize
      height: window.iconSize
      scale: appsSlot.magnification
      transformOrigin: window.popOrigin
      layer.enabled: true
      layer.textureSize: Qt.size(256, 256)
      layer.smooth: true
      Behavior on scale { enabled: !window.positionChanging; NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

      Grid {
        readonly property real square: window.iconSize * 0.26

        anchors.centerIn: parent
        columns: 3
        spacing: window.iconSize * 0.11

        Repeater {
          model: 9

          delegate: Rectangle {
            width: parent.square
            height: parent.square
            radius: Math.max(1, parent.square * 0.2)
            color: Commons.Color.bar.text
          }
        }
      }
    }
  }

  component AppSlot: Slot {
    id: appSlot

    required property int index
    required property string key
    readonly property var modelData: window.dock ? window.dock.itemFor(key) : null
    readonly property bool lifted: window.dragIndex === index
    property point pressPoint
    property bool dragged: false
    readonly property int windowCount: modelData ? modelData.windows.length : 0
    readonly property bool minimized: windowCount > 0 && modelData.windows.every(function(win) { return win.minimized })
    readonly property bool active: !minimized && !!modelData && modelData.windows.some(function(win) { return !!win.toplevel && win.toplevel.activated })
    readonly property int otherWorkspace: {
      if (!modelData || !modelData.windows.length) return -1
      var win = modelData.windows[0]
      var workspace = minimized ? win.sortWorkspaceId : win.workspaceId
      return workspace > 0 ? workspace : -1
    }

    // Slots between where the dragged app was and where it would land step
    // aside to make room; the dragged one follows the pointer.
    readonly property real shift: window.insertIndex >= 0 ? (index >= window.insertIndex ? 1 : -1) * window.slotSize / 2
      : !window.dragging ? 0
      : lifted ? window.dragOffset
      : (window.dragIndex < index && index <= window.dropIndex) ? -window.slotSize
      : (window.dropIndex <= index && index < window.dragIndex) ? window.slotSize
      : 0
    property real displayedShift: shift

    // Only while dragging: once the drop reorders the slots, they are already
    // where they were shown.
    Behavior on displayedShift {
      enabled: !window.positionChanging && window.animateShifts && ((window.dragging && !appSlot.lifted) || window.insertIndex >= 0)
      NumberAnimation { duration: Style.duration(150); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    z: lifted ? 1 : 0

    // The slot, and the pointer handling in it, stays where it is; only the
    // icon moves. Reading the pointer through a slot that moves with it would
    // feed each move back into the next.
    function bodyPoint(event) {
      return appSlot.mapToItem(body, event.x, event.y)
    }

    mouse.onPressed: function(event) {
      appSlot.dragged = false
      if (event.button === Qt.LeftButton) appSlot.pressPoint = appSlot.bodyPoint(event)
    }

    mouse.onPositionChanged: function(event) {
      if (!(appSlot.mouse.pressedButtons & Qt.LeftButton)) return
      var point = appSlot.bodyPoint(event)
      var delta = window.vertical ? point.y - appSlot.pressPoint.y : point.x - appSlot.pressPoint.x
      // Small movements are still clicks. Only a deliberate gesture cancels
      // the click or begins reordering.
      var threshold = Style.space(16)
      // Open instances follow workspace order instead of manual dragging.
      // Still suppress the release click after a drag gesture.
      if (window.dock.instances && appSlot.windowCount > 0) {
        if (Math.hypot(point.x - appSlot.pressPoint.x, point.y - appSlot.pressPoint.y) >= threshold) appSlot.dragged = true
        return
      }
      if (!window.dragging) {
        if (Math.abs(delta) < threshold) return
        appSlot.dragged = true
        window.closeMenu()
        // The landing slot first: with the dragged slot set and no landing
        // slot yet, every slot before it would count as in between and step
        // aside for a moment.
        window.dropIndex = appSlot.index
        window.dragIndex = appSlot.index
      }
      if (!appSlot.lifted) return
      window.dragOffset = delta
      var count = window.dock.instances
        ? window.dock.items.filter(function(item) { return item.windows.length === 0 }).length
        : appRepeater.count
      window.dropIndex = DockModel.dropIndex(appSlot.index, delta, window.slotSize, count)
    }

    mouse.onReleased: function(event) {
      if (!appSlot.lifted) return
      window.dropPoint = appSlot.mapToItem(body, event.x, event.y)
      var from = window.dragIndex
      var to = window.dropIndex
      appSlot.dragged = true
      window.endDrag()
      window.dock.moveItem(from, to)
    }

    mouse.onCanceled: if (appSlot.lifted) window.endDrag()

    mouse.onClicked: function(event) {
      // A drag ends in a release over the app, which is not a click on it.
      if (appSlot.dragged) {
        appSlot.dragged = false
        return
      }
      if (event.button === Qt.RightButton) {
        window.openMenu(appSlot.modelData, appSlot, event.x, event.y)
        return
      }
      window.closeMenu()
      if (event.button === Qt.MiddleButton) {
        window.dock.launch(appSlot.modelData)
      }
      else {
        window.dock.activate(appSlot.modelData, window.workspaceId)
      }
    }

    mouse.onDoubleClicked: function(event) {
      // Let the second release generate its own click, too.
      event.accepted = false
    }

    // Running apps are drawn in full, pinned ones that are not running faded,
    // and one that is starting pulses between the two.
    DockIcon {
      id: appIcon
      x: (appSlot.width - width) / 2
      y: window.iconInset
      visibleHeight: window.iconSize
      originalSource: window.dock && appSlot.modelData ? window.dock.iconFor(appSlot.modelData) : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
      layer.enabled: true
      // Keep the grayscale effect sharp when the icon grows on hover.
      layer.textureSize: Qt.size(Math.ceil(256 * appIcon.artworkRatio), 256)
      layer.smooth: true
      layer.effect: MultiEffect {
        saturation: appSlot.minimized ? -1 : 0
        Behavior on saturation {
          enabled: !window.positionChanging
          NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
        }
      }
      transform: Translate {
        x: window.vertical ? 0 : appSlot.displayedShift
        y: window.vertical ? appSlot.displayedShift : 0
      }
      scale: appSlot.lifted ? 1.15 : appSlot.magnification
      transformOrigin: window.popOrigin

      Behavior on scale { enabled: !window.positionChanging; NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
    }

    Item {
      // Badge shares the icon's geometry and animated transform.
      visible: (window.dock && window.dock.workspaceLabel) && appSlot.otherWorkspace > 0 && window.contentShown
      x: appIcon.x
      y: appIcon.y
      width: appIcon.width
      height: appIcon.height
      scale: appIcon.scale
      transformOrigin: window.popOrigin
      z: 1
      transform: Translate {
        x: window.vertical ? 0 : appSlot.displayedShift
        y: window.vertical ? appSlot.displayedShift : 0
      }
      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        width: workspaceText.implicitWidth + Style.space(7)
        height: workspaceText.implicitHeight + Style.space(3)
        radius: Math.min(Style.cornerRadius, Style.spacing.sm)
        color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.92)
        border.width: Math.max(1, Style.space(1))
        border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.2)
        Text {
          id: workspaceText
          anchors.centerIn: parent
          text: String(appSlot.otherWorkspace > 10
            ? appSlot.otherWorkspace + 10 : appSlot.otherWorkspace)
          textFormat: Text.PlainText
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }
    }

  }

  BorderSurface {
    id: menu

    readonly property var item: window.menuItem
    readonly property bool hasEntry: !!item && !!window.dock && !!window.dock.entryFor(item)
    readonly property bool running: !!item && item.windows.length > 0

    visible: window.contentShown && (!!item || window.settingsMenu)
    width: Math.max(Style.space(140), menuColumn.implicitWidth) + padding * 2
    height: menuColumn.implicitHeight + padding * 2
    x: window.popupX(window.menuSlot, menu)
    y: window.popupY(window.menuSlot, menu)
    radius: Style.cornerRadius
    color: Commons.Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
    padding: Style.spacing.sm

    Column {
      id: menuColumn
      x: menu.contentLeftInset
      y: menu.contentTopInset
      width: menu.width - menu.contentLeftInset - menu.contentRightInset

      Repeater {
        model: [["top", Commons.I18n.t("dock.positionTop")], ["bottom", Commons.I18n.t("dock.positionBottom")], ["left", Commons.I18n.t("dock.positionLeft")], ["right", Commons.I18n.t("dock.positionRight")]]

        delegate: MenuRow {
          required property var modelData

          visible: window.settingsMenu
          text: modelData[1]
          checked: window.position === modelData[0]
          onTriggered: Util.execArgv(["omarchy-dock", "position", modelData[0]])
        }
      }

      MenuRow {
        visible: window.settingsMenu
        text: Commons.I18n.t("dock.autoHide")
        checked: window.autohide
        onTriggered: Util.execArgv(["omarchy-dock", "autohide", window.autohide ? "off" : "on"])
      }

      MenuRow {
        text: Commons.I18n.t("dock.settings")
        onTriggered: {
          window.closeMenu()
          Qt.callLater(function() {
            if (window.dock && window.dock.shell)
              window.dock.shell.summon("omarchy.menu", JSON.stringify({ menu: "appearance.dock" }))
          })
        }
      }

      MenuRow {
        visible: menu.hasEntry && menu.running
        text: Commons.I18n.t("dock.newWindow")
        onTriggered: window.dock.launch(menu.item)
      }

      MenuRow {
        visible: menu.running && menu.item.windows.some(function(win) {
          var workspace = win.minimized ? win.sortWorkspaceId : win.workspaceId
          return workspace > 0 && workspace !== window.workspaceId
        })
        text: Commons.I18n.t("dock.moveHere")
        onTriggered: window.dock.moveHere(menu.item, window.workspaceId)
      }

      MenuRow {
        visible: menu.hasEntry
        text: menu.item && menu.item.pinned ? Commons.I18n.t("dock.removeFromDock") : Commons.I18n.t("dock.keepInDock")
        onTriggered: window.dock.setPinned(menu.item.key, !menu.item.pinned)
      }

      MenuRow {
        visible: menu.running
        text: Commons.I18n.t("dock.quit")
        onTriggered: window.dock.quit(menu.item)
      }
    }
  }

  component MenuRow: Rectangle {
    id: row

    property string text: ""
    property bool checked: false
    signal triggered()

    width: parent ? parent.width : 0
    height: visible ? Style.spacing.popupRowHeight : 0
    radius: Style.cornerRadius
    color: rowMouse.containsMouse ? Style.hoverFill : "transparent"

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX
      textFormat: Text.PlainText
      text: row.text
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      visible: row.checked
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.controlPaddingX
      textFormat: Text.PlainText
      text: "✓"
      color: Commons.Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        row.triggered()
        window.closeMenu()
      }
    }
  }
}
