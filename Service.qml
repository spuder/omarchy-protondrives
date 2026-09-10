import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Owns all Proton Drive account state for the panel. Talks to two helper
// scripts shipped in bin/: `protondrive-status` (read-only, one JSON object
// describing every configured account) and `protondrive-accountctl`
// (add/remove/pause/resume, each a single subcommand). Neither script is
// this plugin's sync engine — they're a thin CLI over rclone and the
// per-account `omarchy-protondrive@<id>.service` systemd user units. See
// PLAN.md for why the daemon lives outside the QML process.
Item {
  id: root

  property var settings: ({})
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")

  property bool rcloneInstalled: false
  property var accounts: []
  property string lastError: ""
  property string actionStatus: ""

  // In-panel login form state (see Panel.qml's LoginForm component). No
  // terminal involved: the form's fields go straight to loginProcess over
  // stdin, the same way the first-party network plugin sends Wi-Fi
  // passwords ("the password goes over stdin, never argv").
  //
  // The field values live here, not as local properties on LoginForm
  // itself — KeyboardPanel only toggles visible/opacity on close, it
  // doesn't destroy its content, but the *form* was still losing every
  // typed field the moment the panel closed and reopened (e.g. clicking
  // out to go copy a password from elsewhere). A component instance is
  // one thing to keep alive across that; the Service instance below,
  // which was never being torn down in the first place, is the one place
  // that's actually guaranteed to survive it.
  property bool loginFormOpen: false
  property bool loginBusy: loginProcess.running
  property string loginError: ""
  property string formId: ""
  property string formDisplayName: ""
  property string formUsername: ""
  property string formPassword: ""
  property bool formHas2fa: false
  property string form2fa: ""
  property bool formHasMailboxPassword: false
  property string formMailboxPassword: ""

  function resetLoginForm() {
    formId = ""; formDisplayName = ""; formUsername = ""; formPassword = ""
    formHas2fa = false; form2fa = ""; formHasMailboxPassword = false; formMailboxPassword = ""
  }

  // Optimistic per-account pause/resume, same idea as the Dropbox plugin's
  // single `_desired` flag but keyed by account id since several accounts
  // can be mid-toggle at once.
  property var _desiredActive: ({})

  readonly property string aggregateState: Model.aggregateState(accounts)
  readonly property string aggregateStatusText: Model.aggregateSummary(accounts)
  readonly property double totalUsedBytes: Model.totalUsedBytes(accounts)
  readonly property bool busy: statusProcess.running || controlProcess.running

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 600)

  property string _statusOutput: ""
  property string _statusError: ""
  property string _controlOutput: ""
  property string _controlError: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function displayActive(account) {
    var desired = root._desiredActive[account.id]
    return desired === undefined ? account.active : desired
  }

  function refresh() {
    if (statusProcess.running) return
    _statusOutput = ""
    _statusError = ""
    statusProcess.command = ["python3", root.pluginDir + "bin/protondrive-status"]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseAccounts(raw)
    if (!parsed.ok) {
      lastError = parsed.lastError || "Failed to read Proton Drive status"
      return
    }
    rcloneInstalled = parsed.rcloneInstalled === true
    accounts = parsed.accounts
    lastError = ""
    // Reality caught up to any pending pause/resume — stop overriding.
    var next = {}
    for (var i = 0; i < accounts.length; i++) {
      var a = accounts[i]
      var desired = root._desiredActive[a.id]
      if (desired !== undefined && desired !== a.active) next[a.id] = desired
    }
    root._desiredActive = next
  }

  function elide(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function toggleAccount(id) {
    var account = accounts.find(function(a) { return a.id === id })
    if (!account || controlProcess.running) return
    var desired = !displayActive(account)
    var next = Object.assign({}, root._desiredActive)
    next[id] = desired
    root._desiredActive = next
    runControl([desired ? "resume" : "pause", id])
  }

  function openMountFolder(account) {
    if (!account || !account.mountPath) return
    Quickshell.execDetached(["uwsm-app", "--", "nautilus", account.mountPath])
  }

  function beginAddAccount() {
    if (loginProcess.running) return
    loginError = ""
    // Deliberately not resetLoginForm() here — reopening the form (the
    // panel was just closed and reopened, or this is a second click) must
    // not wipe fields the user already typed. Only cancelLogin() and a
    // successful submitLogin() clear them.
    loginFormOpen = true
  }

  function cancelLogin() {
    if (loginProcess.running) return  // let an in-flight attempt finish
    loginFormOpen = false
    loginError = ""
    resetLoginForm()
  }

  // payload: {id, displayName, username, password, twofa, mailboxPassword}.
  // Proton's SRP + 2FA + mailbox-password login has no browser hand-off to
  // delegate to (unlike Dropbox's OAuth link) — rclone's protondrive
  // backend does the SRP handshake itself, which means it needs the actual
  // password, not a token. So this is a real password field in a real
  // panel form rather than a terminal prompt, but it's still our form the
  // password is typed into, not Proton's own login page the way the
  // official Proton Drive CLI's browser-based flow is (see PLAN.md — that
  // CLI's sessions turned out not to be usable here at all: rclone's own
  // provider schema marks its equivalent client_uid/client_access_token/
  // client_refresh_token fields "internal use only", and even if extracted
  // a token minted for a different app is unlikely to be honoured by
  // Proton's API for this one). --json on protondrive-accountctl reads
  // this same payload as one JSON line from stdin instead of prompting.
  function submitLogin(payload) {
    if (loginProcess.running) return
    loginError = ""
    loginProcess.payload = JSON.stringify(payload)
    loginProcess.command = ["python3", root.pluginDir + "bin/protondrive-accountctl", "add", "--json"]
    loginProcess.running = true
  }

  function runControl(command) {
    _controlOutput = ""
    _controlError = ""
    controlProcess.command = ["python3", root.pluginDir + "bin/protondrive-accountctl"].concat(command)
    controlProcess.running = true
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 800
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.applyStatus(stdout)
      else root.lastError = root.elide(stderr || stdout || "Could not read Proton Drive status")
    }
  }

  Process {
    id: loginProcess
    running: false
    command: []
    property string payload: ""
    stdinEnabled: true
    onStarted: {
      write(payload + "\n")
      payload = ""  // cleared the instant it's sent — nothing sensitive kept around
    }
    stdout: StdioCollector { id: loginStdout; waitForEnd: true }
    stderr: StdioCollector { id: loginStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var raw = String(loginStdout.text || "").trim()
      var parsed = null
      try { parsed = raw !== "" ? JSON.parse(raw) : null } catch (e) { parsed = null }
      if (parsed && parsed.ok === true) {
        root.loginFormOpen = false
        root.loginError = ""
        root.resetLoginForm()
        root.actionStatus = "Signed in"
        actionStatusTimer.restart()
      } else {
        // Not elide()'d, unlike the other status/tooltip strings in this
        // file — this is the one place the user is actively reading a
        // failure to diagnose it, in a form with room to show it, inside
        // a Flickable that already scrolls. elide()'s 140-char cut was
        // real: it was cutting rclone's actual error message off mid-word
        // before it ever reached the panel, not just wrapping visually.
        var detail = (parsed && parsed.error) || String(loginStderr.text || "").trim() || "Sign-in failed"
        root.loginError = detail
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: controlProcess
    running: false
    command: []
    stdout: StdioCollector { id: controlStdout; waitForEnd: true; onStreamFinished: root._controlOutput = text }
    stderr: StdioCollector { id: controlStderr; waitForEnd: true; onStreamFinished: root._controlError = text }
    onExited: function(exitCode) {
      var stdout = String(controlStdout.text || root._controlOutput || "")
      var stderr = String(controlStderr.text || root._controlError || "")
      if (exitCode !== 0) {
        root.lastError = root.elide(stderr || stdout || "Proton Drive command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      }
      delayedRefresh.restart()
    }
  }
}
