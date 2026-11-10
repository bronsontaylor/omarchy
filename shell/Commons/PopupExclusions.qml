pragma Singleton
import QtQuick
import Quickshell

// Surfaces below a popup may keep input in their visible area. The popup's
// own card is added back afterwards, so its controls always win at overlaps.
Singleton {
  id: root
  property var entries: []

  function add(entry) { entries = entries.concat([entry]) }
  function remove(entry) { entries = entries.filter(function(item) { return item !== entry }) }
  function forScreen(screen) {
    return entries.filter(function(entry) { return entry.enabled && entry.screen === screen })
  }
}
