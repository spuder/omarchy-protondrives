import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar icon + dropdown panel for Proton Drive, covering N accounts. Structure
// mirrors the first-party Dropbox plugin (shell/plugins/panels/dropbox) —
// one Panel.qml owning both the bar button and the KeyboardPanel — but the
// panel body is a repeated account list instead of a single account's file
// list, since that's the whole point of this plugin. See PLAN.md.
Panel {
  id: root
  moduleName: "spencerowen.protondrive"
  ipcTarget: "spencerowen.protondrive"
  manageIpc: false

  property string focusSection: "add"
  property int accountIndex: 0
  property bool cursorActive: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: proton.aggregateState === "syncing" ? barForeground : Qt.darker(barForeground, 1.55)

  function ensureCursor() {
    if (proton.accounts.length === 0) {
      focusSection = "add"
      accountIndex = 0
      return
    }
    if (focusSection !== "accounts" && focusSection !== "add") focusSection = "accounts"
    if (accountIndex >= proton.accounts.length) accountIndex = Math.max(0, proton.accounts.length - 1)
    if (accountIndex < 0) accountIndex = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    if (focusSection === "add") {
      if (dy > 0 && proton.accounts.length > 0) {
        focusSection = "accounts"
        accountIndex = 0
      }
      return
    }
    if (focusSection === "accounts") {
      if (dy < 0 && accountIndex === 0) {
        focusSection = "add"
        return
      }
      accountIndex = Math.max(0, Math.min(proton.accounts.length - 1, accountIndex + dy))
    }
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "add") proton.beginAddAccount()
    else if (focusSection === "accounts") {
      var account = selectedAccount()
      if (account) proton.openMountFolder(account)
    }
  }

  function selectedAccount() {
    if (proton.accounts.length === 0) return null
    return proton.accounts[Math.max(0, Math.min(accountIndex, proton.accounts.length - 1))]
  }

  function setAccountCursor(index) {
    cursorActive = true
    focusSection = "accounts"
    accountIndex = index
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    proton.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: proton
    settings: root.settings
  }

  Connections {
    target: proton
    function onAccountsChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { proton.refresh(); return "ok" }
    function status(): string { return proton.aggregateStatusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        ProtonDriveIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
          opacity: proton.aggregateState === "paused" ? 0.6 : 1.0
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) proton.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") proton.refresh()
        else if (t === "a" || t === "A") proton.beginAddAccount()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "Proton Drives"
            meta: proton.aggregateStatusText
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              ProtonDriveIcon {
                iconSize: Style.font.display
                color: root.foreground
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: !proton.rcloneInstalled
            width: parent.width
            text: "rclone is not installed — run the install script, then add an account."
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            visible: proton.actionStatus !== "" || proton.lastError !== ""
            width: parent.width
            text: proton.actionStatus !== "" ? proton.actionStatus : proton.lastError
            color: proton.lastError !== "" && proton.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          AddAccountButton {
            visible: !proton.loginFormOpen
            width: parent.width
          }

          LoginForm {
            visible: proton.loginFormOpen
            width: parent.width
          }

          PanelSeparator {
            visible: proton.accounts.length > 0
            foreground: root.foreground
          }

          Column {
            visible: proton.accounts.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "ACCOUNTS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: accountColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: proton.accounts
                AccountRow {
                  required property var modelData
                  required property int index
                  width: accountColumn.width
                  account: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  component AddAccountButton: CursorSurface {
    id: addButton

    hasCursor: root.cursorActive && root.focusSection === "add"
    foreground: root.foreground

    implicitHeight: addRow.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.focusSection = "add"
      }
      onClicked: proton.beginAddAccount()
    }

    RowLayout {
      id: addRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: "Add a Proton Drive account"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: "Your password goes straight to rclone over stdin — never typed anywhere else"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: "+"
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: proton.beginAddAccount()
      }
    }
  }

  component LoginForm: Column {
    id: loginForm
    spacing: Style.space(8)

    // Bound straight to Service.qml's persistent form* properties, not
    // local state — see the comment there for why (typed fields were
    // being wiped on every panel close/reopen otherwise, e.g. clicking
    // out to go copy a password from somewhere else).
    readonly property bool canSubmit: proton.formId.trim() !== "" && proton.formUsername.trim() !== "" &&
                                       proton.formPassword !== "" && !proton.loginBusy

    function submit() {
      if (!canSubmit) return
      proton.submitLogin({
        id: proton.formId.trim().toLowerCase(),
        displayName: proton.formDisplayName.trim(),
        username: proton.formUsername.trim(),
        password: proton.formPassword,
        twofa: proton.formHas2fa ? proton.form2fa : "",
        mailboxPassword: proton.formHasMailboxPassword ? proton.formMailboxPassword : ""
      })
    }

    onVisibleChanged: if (visible) Qt.callLater(function() { idField.forceActiveFocus() })

    PanelSectionHeader {
      text: "SIGN IN"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    LoginField {
      id: idField
      label: "Account id (e.g. personal)"
      text: proton.formId
      onTextEdited: proton.formId = text
      onAccepted: loginForm.submit()
      KeyNavigation.tab: displayNameField
    }
    LoginField {
      id: displayNameField
      label: "Display name (optional)"
      text: proton.formDisplayName
      onTextEdited: proton.formDisplayName = text
      onAccepted: loginForm.submit()
      KeyNavigation.tab: usernameField
    }
    LoginField {
      id: usernameField
      label: "Proton account email"
      text: proton.formUsername
      onTextEdited: proton.formUsername = text
      onAccepted: loginForm.submit()
      KeyNavigation.tab: passwordField
    }
    LoginField {
      id: passwordField
      label: "Proton account password"
      text: proton.formPassword
      password: true
      onTextEdited: proton.formPassword = text
      onAccepted: loginForm.submit()
      KeyNavigation.tab: twofaCheck
    }

    RowLayout {
      width: parent.width
      spacing: Style.space(6)
      CheckBox {
        id: twofaCheck
        checked: proton.formHas2fa
        onToggled: proton.formHas2fa = checked
        KeyNavigation.tab: mailboxCheck
      }
      Text {
        text: "Two-factor authentication enabled"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
    LoginField {
      label: "2FA code"
      visible: proton.formHas2fa
      text: proton.form2fa
      onTextEdited: proton.form2fa = text
      onAccepted: loginForm.submit()
    }

    RowLayout {
      width: parent.width
      spacing: Style.space(6)
      CheckBox {
        id: mailboxCheck
        checked: proton.formHasMailboxPassword
        onToggled: proton.formHasMailboxPassword = checked
      }
      Text {
        text: "Separate mailbox password (old accounts only)"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }
    LoginField {
      label: "Mailbox password"
      visible: proton.formHasMailboxPassword
      text: proton.formMailboxPassword
      password: true
      onTextEdited: proton.formMailboxPassword = text
      onAccepted: loginForm.submit()
    }

    Text {
      textFormat: Text.PlainText
      visible: proton.loginError !== ""
      width: parent.width
      text: proton.loginError
      color: root.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    RowLayout {
      width: parent.width
      spacing: Style.space(8)

      PanelActionButton {
        iconText: "×"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !proton.loginBusy
        onClicked: proton.cancelLogin()
      }

      BusyIndicator {
        // Contacting Proton is one blocking `rclone config create` call
        // (up to 60s) followed by one `rclone about` verification (up to
        // 30s) — no percentage to report, so this is deliberately
        // indeterminate rather than a fake progress bar. Was previously
        // just static "Signing in…" text, easy to miss and gave no sense
        // that anything was actually moving.
        Layout.preferredWidth: Style.space(18)
        Layout.preferredHeight: Style.space(18)
        visible: proton.loginBusy
        running: proton.loginBusy
      }
      Text {
        Layout.fillWidth: true
        text: proton.loginBusy ? "Signing in — this can take up to a minute or two…" : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
      PanelActionButton {
        iconText: "✓"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: loginForm.canSubmit
        onClicked: loginForm.submit()
      }
    }
  }

  component LoginField: ColumnLayout {
    id: fieldRoot
    property alias label: labelText.text
    property alias text: input.text
    property bool password: false
    signal textEdited()
    signal accepted()

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(2)

    Text {
      id: labelText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    TextField {
      id: input
      Layout.fillWidth: true
      echoMode: fieldRoot.password ? TextInput.Password : TextInput.Normal
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      onTextChanged: fieldRoot.textEdited()
      Keys.onReturnPressed: fieldRoot.accepted()
    }
  }

  component AccountRow: CursorSurface {
    id: accountRow
    property var account: null
    property int rowIndex: 0
    readonly property bool active: account ? proton.displayActive(account) : false
    readonly property color statusColor: !account ? root.dim
      : account.lastError !== "" ? root.urgent
      : active ? root.foreground : root.dim

    hasCursor: root.cursorActive && root.focusSection === "accounts" && root.accountIndex === rowIndex
    foreground: root.foreground

    implicitHeight: accountContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setAccountCursor(accountRow.rowIndex)
      onClicked: proton.openMountFolder(accountRow.account)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Rectangle {
        width: Style.space(8)
        height: width
        radius: width / 2
        color: accountRow.statusColor
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: accountContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: accountRow.account ? accountRow.account.displayName : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: accountRow.account
            ? (accountRow.account.lastError !== "" ? accountRow.account.lastError
              : Model.usageText(accountRow.account.usedBytes, accountRow.account.quotaBytes, accountRow.account.quotaKnown))
            : ""
          color: accountRow.account && accountRow.account.lastError !== "" ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      ToggleSwitch {
        visible: accountRow.account ? accountRow.account.authenticated : false
        checked: accountRow.active
        busy: proton.busy
        hasCursor: false
        foreground: root.foreground
        Layout.alignment: Qt.AlignVCenter
        onToggled: if (accountRow.account) proton.toggleAccount(accountRow.account.id)

        PanelToolTip {
          visible: parent.containsMouse
          text: accountRow.active ? "Pause syncing" : "Resume syncing"
          fontFamily: root.fontFamily
        }
      }
    }
  }
}
