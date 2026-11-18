import QtQuick
import Quickshell.Io

// A small local file's text, read synchronously on first use and on every
// change; bind to `text` as to FileView's text(). Every read is synchronous
// because FileView's reload() joins a background read already running, which
// would keep a deleted or replaced file's old contents.
QtObject {
  id: root

  property string path: ""
  readonly property string text: reader.text()

  // Keep the current watch alive while readers publish dependent bindings.
  // Rearming inside its fileChanged callback can discard a change made during
  // that publication. Coalesce the rearm until the callback has unwound.
  function reread() {
    reader.reload()
    Qt.callLater(root.rearm)
  }

  function rearm() {
    watcher.reload()
    // Catch changes during the rearm as well as edits to a replacement whose
    // old inode is still alive under another name.
    reader.reload()
  }

  // Both FileViews follow `path` in no set order, so read again once both have.
  onPathChanged: Qt.callLater(function() { root.reader.reload() })

  readonly property FileView reader: FileView {
    path: root.path
    printErrors: false
    preload: false
    blockAllReads: true
  }

  readonly property FileView watcher: FileView {
    path: root.path
    watchChanges: true
    printErrors: false
    preload: false
    onFileChanged: root.reread()
  }
}
