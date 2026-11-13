import QtQuick
import Quickshell.Io

// Keep the watch alive while a synchronous read publishes new bindings.
// FileView.reload() rebuilds its watcher after textChanged: a caller that
// changes the file during that notification can otherwise lose the event.
QtObject {
  id: root

  property string path: ""

  function text() {
    // Arm the new path before any read can notify its callers. The watcher
    // never reloads its own contents, so updates do not replace its watch.
    watcher.path = root.path
    return reader.text()
  }

  property FileView watcher: FileView {
    preload: false
    printErrors: false
    watchChanges: true
    onFileChanged: reader.reload()
  }

  property FileView reader: FileView {
    path: root.path
    preload: false
    printErrors: false
    blockAllReads: true
  }
}
