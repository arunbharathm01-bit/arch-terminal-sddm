pragma ComponentBehavior: Bound

// Arch Terminal — SDDM 0.21+ theme for Plasma 6 / Qt 6.
//
// This theme relies only on Qt 6 modules and the documented SDDM context
// objects: `sddm`, `sessionModel`, `userModel`, and `config`.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Rectangle {
    id: root
    color: "#000000"
    focus: true

    // ----- Configuration ---------------------------------------------------
    // Every user-facing visual/timing setting is read through SDDM's typed
    // config API. Defaults are present in theme.conf.
    property color textColor: config.stringValue("TextColor")
    property color dimTextColor: config.stringValue("DimTextColor")
    property color cursorColor: config.stringValue("CursorColor")
    property color panelColor: config.stringValue("PanelColor")
    property color panelBorderColor: config.stringValue("PanelBorderColor")
    property url backgroundSource: config.stringValue("Background")
    property int typingSpeed: Math.max(10, config.intValue("TypingSpeed"))
    property int bootDelay: Math.max(0, config.intValue("BootDelay"))
    property int bootSettleDelay: Math.max(0, config.intValue("BootSettleDelay"))
    property int animationDuration: Math.max(1, config.intValue("AnimationDuration"))
    property real backgroundOpacity: Math.max(0.0, Math.min(1.0,
                                                              config.realValue("BackgroundOpacity")))
    property real backgroundBlur: Math.max(0.0, Math.min(1.0,
                                                          config.realValue("BackgroundBlur")))
    property int panelWidth: Math.min(710, Math.max(440, width * 0.52))

    // ----- Boot state ------------------------------------------------------
    property bool loginReady: false
    property bool loginPending: false
    property string loginError: ""
    property int bootLineIndex: 0
    property int typedCharacterCount: 0
    property string activeBootLine: ""
    property int visibleLogoLines: 0
    property var archLogoLines: [
        "       /\\",
        "      /  \\",
        "     /\\   \\",
        "    /      \\",
        "   /   ,,   \\",
        "  /   |  |  -\\",
        " /_-''    ''-_\\"
    ]
    property var bootMessages: [
        "Initializing Arch Linux...",
        "Loading kernel...",
        "Mounting root filesystem...",
        "Starting systemd...",
        "Loading NetworkManager...",
        "Loading Bluetooth...",
        "Loading PipeWire...",
        "Starting Plasma...",
        "Checking filesystem integrity...",
        "Loading user environment...",
        "Initializing graphics...",
        "Launching login service..."
    ]

    // The bundled, open-font-licensed file keeps JetBrains Mono available to
    // SDDM without requiring a separate system font package.
    FontLoader {
        id: jetbrainsMono
        source: "assets/fonts/JetBrainsMono-Regular.ttf"
    }

    property string terminalFont: jetbrainsMono.status === FontLoader.Ready
                                  ? jetbrainsMono.name : "monospace"

    // ----- SDDM actions ----------------------------------------------------
    // Authentication is delegated to SDDM/PAM. The theme never handles or
    // validates credentials itself.
    function submitLogin() {
        if (loginPending)
            return

        var username = usernameField.text.trim()
        if (username.length === 0) {
            loginError = "login: username is required"
            usernameField.forceActiveFocus()
            return
        }

        if (passwordField.text.length === 0) {
            loginError = "login: password is required"
            passwordField.forceActiveFocus()
            return
        }

        loginError = ""
        loginPending = true
        // Official SDDM API: the selected session's index is argument three.
        sddm.login(username, passwordField.text, sessionSelector.currentIndex)
    }

    // Keyboard equivalents match the labels in the terminal command bar.
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_F1 && sddm.canPowerOff) {
            sddm.powerOff()
            event.accepted = true
        } else if (event.key === Qt.Key_F2 && sddm.canReboot) {
            sddm.reboot()
            event.accepted = true
        } else if (event.key === Qt.Key_F3 && sddm.canSuspend) {
            sddm.suspend()
            event.accepted = true
        }
    }

    // ----- Character-by-character boot typer -----------------------------
    // The completed model holds previous lines; activeBootLine is rendered
    // separately so its text can grow by one character on every timer tick.
    ListModel {
        id: bootLog
    }

    function beginNextBootLine() {
        if (bootLineIndex >= bootMessages.length) {
            bootSettleTimer.start()
            return
        }

        activeBootLine = bootMessages[bootLineIndex]
        typedCharacterCount = 0
        typingTimer.start()
    }

    Timer {
        id: typingTimer
        interval: root.typingSpeed
        repeat: true

        onTriggered: {
            if (root.typedCharacterCount < root.activeBootLine.length) {
                root.typedCharacterCount += 1
                return
            }

            bootLog.append({ "line": root.activeBootLine })
            bootList.positionViewAtEnd()
            root.bootLineIndex += 1
            root.activeBootLine = ""
            root.typedCharacterCount = 0
            stop()
            bootDelayTimer.start()
        }
    }

    // A configurable pause after each completed line makes the output read as
    // a plausible console boot rather than a wall of instantly rendered text.
    Timer {
        id: bootDelayTimer
        interval: root.bootDelay
        repeat: false
        onTriggered: root.beginNextBootLine()
    }

    // Preserve the final boot screen for a short moment before login fades in.
    Timer {
        id: bootSettleTimer
        interval: root.bootSettleDelay
        repeat: false
        onTriggered: {
            root.loginReady = true
            loginFocusTimer.start()
        }
    }

    // Focus moves only after the prompt becomes visible, preventing keystrokes
    // from being received by an invisible input field during boot.
    Timer {
        id: loginFocusTimer
        interval: Math.min(300, root.animationDuration / 2)
        repeat: false
        onTriggered: {
            if (usernameField.text.length === 0)
                usernameField.forceActiveFocus()
            else
                passwordField.forceActiveFocus()
        }
    }

    // Animate the ASCII Arch mark one line at a time in parallel with boot.
    Timer {
        id: logoTimer
        interval: Math.max(45, root.typingSpeed * 3)
        repeat: true
        running: root.visibleLogoLines < root.archLogoLines.length
        triggeredOnStart: true
        onTriggered: root.visibleLogoLines += 1
    }

    Component.onCompleted: beginNextBootLine()

    // ----- Wallpaper, blur, and low-contrast terminal treatment ----------
    // MultiEffect is Qt 6's supported replacement for the deprecated
    // QtGraphicalEffects module. The source stays hidden; MultiEffect renders
    // the blurred result at screen size without extra padding.
    Image {
        id: wallpaper
        anchors.fill: parent
        source: root.backgroundSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        autoPaddingEnabled: false
        blurEnabled: root.backgroundBlur > 0
        blurMax: 16
        blur: root.backgroundBlur
        brightness: -0.12
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: root.backgroundOpacity
    }

    // ----- Very subtle CRT atmosphere -------------------------------------
    // Static scan lines are inexpensive; an occasional low-opacity flash adds
    // a restrained flicker without disturbing text readability.
    Repeater {
        model: 135
        Rectangle {
            required property int index
            width: root.width
            height: 1
            y: index * root.height / 135
            color: "#baffae"
            opacity: 0.028
        }
    }

    Rectangle {
        id: crtFlicker
        anchors.fill: parent
        color: root.textColor

        SequentialAnimation on opacity {
            loops: Animation.Infinite
            PropertyAction { value: 0 }
            PauseAnimation { duration: 4400 }
            NumberAnimation { to: 0.018; duration: 35 }
            NumberAnimation { to: 0; duration: 90 }
        }
    }

    // ----- Terminal header -------------------------------------------------
    Text {
        id: terminalHeader
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: Math.max(30, root.width * 0.05)
        anchors.topMargin: Math.max(24, root.height * 0.04)
        text: "Arch Linux 6.x  (tty1)   " + sddm.hostname
        color: root.dimTextColor
        font.family: root.terminalFont
        font.pixelSize: Math.max(12, Math.min(17, root.width / 110))
    }

    Rectangle {
        anchors.left: terminalHeader.left
        anchors.right: parent.right
        anchors.rightMargin: terminalHeader.anchors.leftMargin
        anchors.top: terminalHeader.bottom
        anchors.topMargin: 10
        height: 1
        color: root.dimTextColor
        opacity: 0.52
    }

    // ----- Boot console ----------------------------------------------------
    // This fades into the background when the login prompt is ready, leaving
    // the completed console visible through the transparent terminal panel.
    Item {
        id: bootStage
        anchors.fill: parent
        opacity: root.loginReady ? 0.39 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: root.animationDuration
                easing.type: Easing.InOutQuad
            }
        }

        Text {
            id: archLogo
            anchors.left: parent.left
            anchors.top: terminalHeader.bottom
            anchors.leftMargin: Math.max(38, root.width * 0.085)
            anchors.topMargin: Math.max(52, root.height * 0.095)
            text: root.archLogoLines.slice(0, root.visibleLogoLines).join("\n")
            textFormat: Text.PlainText
            color: root.textColor
            font.family: root.terminalFont
            font.pixelSize: Math.max(14, Math.min(21, root.width / 85))
            lineHeight: 0.90
        }

        Column {
            id: bootColumn
            anchors.left: archLogo.right
            anchors.right: parent.right
            anchors.top: archLogo.top
            anchors.leftMargin: Math.max(34, root.width * 0.055)
            anchors.rightMargin: Math.max(38, root.width * 0.08)
            spacing: 14

            Text {
                text: "BOOTING ARCH LINUX"
                color: root.textColor
                font.family: root.terminalFont
                font.pixelSize: Math.max(15, Math.min(22, root.width / 70))
                font.bold: true
            }

            Text {
                text: "[    0.000000] Linux version 6.x-arch1-1 (x86_64)"
                color: root.dimTextColor
                font.family: root.terminalFont
                font.pixelSize: Math.max(11, Math.min(15, root.width / 110))
            }

            ListView {
                id: bootList
                width: parent.width
                height: Math.max(195, Math.min(root.height * 0.39, 340))
                model: bootLog
                clip: true
                spacing: 5

                delegate: Text {
                    required property string line
                    width: bootList.width
                    text: line
                    color: root.textColor
                    font.family: root.terminalFont
                    font.pixelSize: Math.max(12, Math.min(17, root.width / 104))
                }
            }

            // This is the only line that changes per keystroke. Once complete,
            // it is moved to bootLog and becomes a stable ListView delegate.
            Row {
                spacing: 3

                Text {
                    id: activeBootText
                    text: root.activeBootLine.substring(0, root.typedCharacterCount)
                    color: root.textColor
                    font.family: root.terminalFont
                    font.pixelSize: Math.max(12, Math.min(17, root.width / 104))
                }

                Rectangle {
                    id: bootCursor
                    width: Math.max(8, activeBootText.font.pixelSize * 0.52)
                    height: Math.max(16, activeBootText.font.pixelSize * 1.12)
                    color: root.cursorColor
                    property bool lit: true
                    opacity: lit ? 1 : 0

                    Timer {
                        interval: 500
                        repeat: true
                        running: !root.loginReady
                        onTriggered: bootCursor.lit = !bootCursor.lit
                    }
                }
            }
        }
    }

    // ----- Reusable input block cursor ------------------------------------
    // The same delegate is used by username and password fields for a terminal
    // block cursor that blinks independently of the boot animation.
    Component {
        id: terminalCursor

        Rectangle {
            id: cursorRectangle
            width: 10
            height: parent ? Math.max(16, parent.height * 0.62) : 18
            color: root.cursorColor
            property bool lit: true
            opacity: lit ? 0.96 : 0

            Timer {
                interval: 520
                repeat: true
                running: true
                onTriggered: cursorRectangle.lit = !cursorRectangle.lit
            }
        }
    }

    // ----- Terminal login prompt ------------------------------------------
    // The panel uses an alpha color rather than reducing item opacity, keeping
    // the text crisp while the wallpaper and finished boot remain visible.
    Rectangle {
        id: loginPanel
        width: root.panelWidth
        height: loginLayout.implicitHeight + 48
        x: (root.width - width) / 2
        y: root.loginReady
           ? Math.min(root.height - height - 62, Math.max(130, root.height * 0.46))
           : Math.min(root.height - height - 62, Math.max(168, root.height * 0.58))
        color: root.panelColor
        opacity: root.loginReady ? 1 : 0
        border.width: 1
        border.color: root.panelBorderColor
        radius: 1
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: root.animationDuration
                easing.type: Easing.OutCubic
            }
        }
        Behavior on y {
            NumberAnimation {
                duration: root.animationDuration
                easing.type: Easing.OutCubic
            }
        }

        ColumnLayout {
            id: loginLayout
            anchors.fill: parent
            anchors.margins: 24
            spacing: 12

            Text {
                Layout.fillWidth: true
                text: "Arch Linux 6.x\nKernel ready.\n\narchlinux login:"
                color: root.textColor
                font.family: root.terminalFont
                font.pixelSize: Math.max(14, Math.min(18, root.width / 97))
                lineHeight: 1.10
            }

            TextField {
                id: usernameField
                Layout.fillWidth: true
                enabled: !root.loginPending
                text: userModel.lastUser
                placeholderText: "username"
                placeholderTextColor: root.dimTextColor
                color: root.textColor
                cursorDelegate: terminalCursor
                selectByMouse: true
                font.family: root.terminalFont
                font.pixelSize: Math.max(14, Math.min(18, root.width / 97))
                background: Rectangle {
                    color: "transparent"
                    border.width: usernameField.activeFocus ? 1 : 0
                    border.color: root.panelBorderColor
                }
                onAccepted: passwordField.forceActiveFocus()
                onTextEdited: root.loginError = ""
            }

            Text {
                Layout.fillWidth: true
                text: "Password:"
                color: root.textColor
                font.family: root.terminalFont
                font.pixelSize: Math.max(14, Math.min(18, root.width / 97))
            }

            TextField {
                id: passwordField
                Layout.fillWidth: true
                enabled: !root.loginPending
                echoMode: TextInput.Password
                passwordCharacter: "•"
                placeholderText: "password"
                placeholderTextColor: root.dimTextColor
                color: root.textColor
                cursorDelegate: terminalCursor
                selectByMouse: true
                font.family: root.terminalFont
                font.pixelSize: Math.max(14, Math.min(18, root.width / 97))
                background: Rectangle {
                    color: "transparent"
                    border.width: passwordField.activeFocus ? 1 : 0
                    border.color: root.panelBorderColor
                }
                onAccepted: root.submitLogin()
                onTextEdited: root.loginError = ""
            }

            // SDDM provides the model of installed desktop sessions. Qt's
            // standard ComboBox displays each model entry's documented name.
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    Layout.preferredWidth: 94
                    text: "Session:"
                    color: root.dimTextColor
                    font.family: root.terminalFont
                    font.pixelSize: Math.max(12, Math.min(16, root.width / 112))
                }

                ComboBox {
                    id: sessionSelector
                    Layout.fillWidth: true
                    enabled: !root.loginPending
                    model: sessionModel
                    textRole: "name"
                    currentIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0

                    contentItem: Text {
                        leftPadding: 10
                        rightPadding: sessionSelector.indicator.width + 8
                        text: sessionSelector.displayText || "No session available"
                        color: root.textColor
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                        font.family: root.terminalFont
                        font.pixelSize: Math.max(12, Math.min(16, root.width / 112))
                    }

                    indicator: Text {
                        x: sessionSelector.width - width - 10
                        y: (sessionSelector.height - height) / 2
                        text: sessionSelector.popup.visible ? "▴" : "▾"
                        color: root.textColor
                        font.family: root.terminalFont
                        font.pixelSize: Math.max(12, Math.min(16, root.width / 112))
                    }

                    background: Rectangle {
                        color: "#98040a05"
                        border.width: 1
                        border.color: sessionSelector.activeFocus
                                      ? root.textColor : root.panelBorderColor
                    }

                    delegate: ItemDelegate {
                        id: sessionDelegate
                        required property int index
                        width: sessionSelector.width
                        highlighted: sessionSelector.highlightedIndex === sessionDelegate.index
                        contentItem: Text {
                            text: sessionSelector.textAt(sessionDelegate.index)
                            color: root.textColor
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                            font.family: root.terminalFont
                            font.pixelSize: Math.max(12, Math.min(16, root.width / 112))
                        }
                        background: Rectangle {
                            color: sessionDelegate.highlighted ? "#502b6e35" : "#d0050b06"
                        }
                    }

                    popup: Popup {
                        y: sessionSelector.height - 1
                        width: sessionSelector.width
                        implicitHeight: Math.min(contentItem.implicitHeight + 4,
                                                  root.height * 0.34)
                        padding: 2
                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            model: sessionSelector.delegateModel
                            currentIndex: sessionSelector.highlightedIndex
                            ScrollIndicator.vertical: ScrollIndicator { }
                        }
                        background: Rectangle {
                            color: "#ec040a05"
                            border.width: 1
                            border.color: root.panelBorderColor
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 10

                Button {
                    id: loginButton
                    Layout.preferredWidth: 126
                    Layout.preferredHeight: 34
                    enabled: !root.loginPending
                    text: root.loginPending ? "AUTH..." : "LOGIN"
                    onClicked: root.submitLogin()
                    contentItem: Text {
                        text: loginButton.text
                        color: "#001500"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.family: root.terminalFont
                        font.pixelSize: Math.max(11, Math.min(15, root.width / 118))
                        font.bold: true
                    }
                    background: Rectangle {
                        color: loginButton.down ? root.dimTextColor : root.textColor
                        border.width: 1
                        border.color: root.textColor
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "Enter = login"
                    color: root.dimTextColor
                    font.family: root.terminalFont
                    font.pixelSize: Math.max(10, Math.min(13, root.width / 134))
                }
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.loginError
                color: "#ff9090"
                wrapMode: Text.Wrap
                font.family: root.terminalFont
                font.pixelSize: Math.max(11, Math.min(14, root.width / 120))
            }
        }
    }

    // ----- Bottom terminal command bar ------------------------------------
    // Buttons stay visible even when unavailable; SDDM's capability flags
    // disable unsupported actions instead of implying they would work.
    Row {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: Math.max(30, root.width * 0.05)
        anchors.bottomMargin: Math.max(20, root.height * 0.035)
        spacing: 18

        Button {
            id: shutdownButton
            enabled: sddm.canPowerOff && !root.loginPending
            text: "[F1] Shutdown"
            onClicked: sddm.powerOff()
            contentItem: Text {
                text: shutdownButton.text
                color: shutdownButton.enabled ? root.textColor : root.dimTextColor
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.family: root.terminalFont
                font.pixelSize: Math.max(10, Math.min(14, root.width / 125))
            }
            background: Rectangle {
                color: shutdownButton.down ? "#382b6e35" : "transparent"
                border.width: 1
                border.color: root.panelBorderColor
            }
        }

        Button {
            id: rebootButton
            enabled: sddm.canReboot && !root.loginPending
            text: "[F2] Reboot"
            onClicked: sddm.reboot()
            contentItem: Text {
                text: rebootButton.text
                color: rebootButton.enabled ? root.textColor : root.dimTextColor
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.family: root.terminalFont
                font.pixelSize: Math.max(10, Math.min(14, root.width / 125))
            }
            background: Rectangle {
                color: rebootButton.down ? "#382b6e35" : "transparent"
                border.width: 1
                border.color: root.panelBorderColor
            }
        }

        Button {
            id: suspendButton
            enabled: sddm.canSuspend && !root.loginPending
            text: "[F3] Sleep"
            onClicked: sddm.suspend()
            contentItem: Text {
                text: suspendButton.text
                color: suspendButton.enabled ? root.textColor : root.dimTextColor
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.family: root.terminalFont
                font.pixelSize: Math.max(10, Math.min(14, root.width / 125))
            }
            background: Rectangle {
                color: suspendButton.down ? "#382b6e35" : "transparent"
                border.width: 1
                border.color: root.panelBorderColor
            }
        }
    }

    // ----- SDDM authentication result handling ---------------------------
    // `loginFailed` and `loginSucceeded` are emitted by SDDM after the PAM
    // transaction started by submitLogin().
    Connections {
        target: sddm

        function onLoginFailed() {
            root.loginPending = false
            root.loginError = "Login incorrect. Please try again."
            passwordField.text = ""
            passwordField.forceActiveFocus()
        }

        function onLoginSucceeded() {
            root.loginPending = false
        }
    }
}
