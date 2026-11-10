import QtQuick
import Quickshell.Io

Image {
  id: icon
  property string originalSource: ""
  property string renderedSource: ""
  property real artworkRatio: 1
  property real visibleHeight: 36
  width: visibleHeight * artworkRatio
  height: visibleHeight
  source: renderedSource
  sourceSize: Qt.size(Math.ceil(256 * artworkRatio), 256)
  onOriginalSourceChanged: {
    // Retain the previous normalized icon until its replacement is ready.
    // Raw theme artwork can have very different transparent padding.
    if (!originalSource) { renderedSource = ""; artworkRatio = 1; return }
    if (originalSource) Qt.callLater(startNormalization)
  }
  function startNormalization() {
    if (!originalSource) return
    if (normalize.running) { normalize.execPending = true; return }
    normalize.requestedSource = originalSource
    normalize.command = ["omarchy-dock-icon", originalSource]
    normalize.running = true
  }
  Process {
    id: normalize
    property string requestedSource: ""
    property bool execPending: false
    stdout: StdioCollector {
      onStreamFinished: {
        if (normalize.requestedSource !== icon.originalSource) return
        try {
          var result = JSON.parse(text)
          icon.artworkRatio = result.ratio
          icon.renderedSource = result.source
        } catch (error) {}
      }
    }
    onExited: if (execPending) { execPending = false; Qt.callLater(icon.startNormalization) }
  }
}
