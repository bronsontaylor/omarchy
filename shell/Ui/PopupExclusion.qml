import QtQuick
import Quickshell
import qs.Commons as Commons

// A visible surface below a popup keeps input in its screen-local region.
// TransformWatcher follows sliding, resizing and menu repositioning directly.
Item {
  id: root
  property string screen: ""
  property Item target: null
  property Item reference: null
  property point offset: Qt.point(0, 0)
  readonly property rect rect: {
    tracker.transform
    if (!target || !reference) return Qt.rect(0, 0, 0, 0)
    var point = target.mapToItem(reference, 0, 0)
    return Qt.rect(point.x + offset.x, point.y + offset.y, target.width, target.height)
  }
  TransformWatcher { id: tracker; a: root.target; b: root.reference }
  Component.onCompleted: Commons.PopupExclusions.add(root)
  Component.onDestruction: Commons.PopupExclusions.remove(root)
}
