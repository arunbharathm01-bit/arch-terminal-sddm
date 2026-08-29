pragma ComponentBehavior: Bound

// Arch Terminal — SDDM 0.21+ theme for Plasma 6 / Qt 6.
//
// This theme relies only on Qt 6 modules and the documented SDDM context
// objects: `sddm`, `sessionModel`, `userModel`, and `config`.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

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
    // Keep a shared grid across the header, boot console, login panel, and
    // command bar. The compact branch is used by tablets and short displays.
    property int horizontalMargin: Math.round(Math.max(22, Math.min(78, width * 0.055)))
    property int verticalMargin: Math.round(Math.max(18, Math.min(48, height * 0.04)))
    property bool compactLayout: width < 980 || height < 680
    property bool compactBootLayout: width < 900 || height < 620
    property int panelPadding: compactLayout ? 18 : 26
    property int panelSpacing: compactLayout ? 9 : 13
    property int loginFontSize: Math.max(13, Math.min(18, width / 97))
    property int detailFontSize: Math.max(10, Math.min(14, width / 124))
    property int logoReservedHeight: Math.ceil(Math.max(14, Math.min(21, width / 85)) * 6.6)
    property int panelWidth: Math.min(720, Math.max(0, width - horizontalMargin * 2))
    property int footerClearance: commandBar.height + verticalMargin + 18

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
        "Initializing " + distributionName + "...",
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

    // SystemInfo.qml is atomically generated under /run before SDDM starts by
    // helpers/arch-terminal-system-info. Loader is native QML file loading,
    // not shell execution or XMLHttpRequest, so the greeter stays sandboxed.
    Loader {
        id: systemInfoLoader
        source: "file:///run/sddm/arch-terminal/SystemInfo.qml"
        asynchronous: false
    }

    // Fall back to neutral text only when the v1.2 helper has not yet been
    // installed. A normal installation always supplies both runtime values.
    property var systemInfo: systemInfoLoader.item
    property string distributionName: systemInfo && systemInfo["distributionName"]
                                      ? systemInfo["distributionName"] : "Linux"
    property string kernelRelease: systemInfo && systemInfo["kernelRelease"]
                                   ? systemInfo["kernelRelease"] : "unknown"
    property string runningKernelLabel: "Linux " + kernelRelease

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
        interval: Math.max(150, Math.min(420, root.animationDuration * 0.72))
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

    // ----- CPU-safe wallpaper and terminal treatment ----------------------
    // Render the image directly. There are no shaders, layers, blur effects,
    // or Qt Graphical Effects in this theme; the dark overlay supplies the
    // needed terminal contrast using only a normal Rectangle opacity value.
    Image {
        id: wallpaper
        anchors.fill: parent
        source: root.backgroundSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
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
        anchors.leftMargin: root.horizontalMargin
        anchors.topMargin: root.verticalMargin
        text: root.distributionName + "  (tty1)   " + sddm.hostname
        color: root.dimTextColor
        font.family: root.terminalFont
        font.pixelSize: Math.max(12, Math.min(17, root.width / 110))
    }

    Rectangle {
        anchors.left: terminalHeader.left
        anchors.right: parent.right
        anchors.rightMargin: root.horizontalMargin
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
            // Stack the logo above the boot log on narrow or short screens;
            // keep the classic side-by-side terminal layout everywhere else.
            x: root.horizontalMargin
            y: terminalHeader.y + terminalHeader.height
               + (root.compactBootLayout ? 30 : Math.max(48, root.height * 0.09))
            text: root.archLogoLines.slice(0, root.visibleLogoLines).join("\n")
            textFormat: Text.PlainText
            color: root.textColor
            font.family: root.terminalFont
            font.pixelSize: Math.max(14, Math.min(21, root.width / 85))
            lineHeight: 0.90
        }

        Column {
            id: bootColumn
            x: root.compactBootLayout
               ? root.horizontalMargin
               : archLogo.x + archLogo.width + Math.max(28, root.width * 0.045)
            y: root.compactBootLayout
               ? archLogo.y + root.logoReservedHeight + 20
               : archLogo.y
            width: root.width - x - root.horizontalMargin
            spacing: root.compactLayout ? 10 : 14

            Text {
                text: "BOOTING " + root.distributionName.toUpperCase()
                color: root.textColor
                font.family: root.terminalFont
                font.pixelSize: Math.max(15, Math.min(22, root.width / 70))
                font.bold: true
            }

            Text {
                text: "[    0.000000] " + root.runningKernelLabel
                color: root.dimTextColor
                font.family: root.terminalFont
                font.pixelSize: Math.max(11, Math.min(15, root.width / 110))
            }

            ListView {
                id: bootList
                width: parent.width
                height: root.compactLayout
                        ? Math.max(122, Math.min(root.height * 0.25, 205))
                        : Math.max(195, Math.min(root.height * 0.39, 340))
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

                    Behavior on opacity {
                        NumberAnimation { duration: 90; easing.type: Easing.InOutQuad }
                    }

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

            Behavior on opacity {
                NumberAnimation { duration: 90; easing.type: Easing.InOutQuad }
            }

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
        height: loginLayout.implicitHeight + root.panelPadding * 2
        x: (root.width - width) / 2
        y: root.loginReady
           ? Math.max(12, Math.min(root.height - height - root.footerClearance,
                                   Math.max(terminalHeader.bottom + 24, root.height * 0.45)))
           : Math.max(12, Math.min(root.height - height - root.footerClearance,
                                   Math.max(terminalHeader.bottom + 44, root.height * 0.59)))
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
            anchors.margins: root.panelPadding
            spacing: root.panelSpacing

            Text {
                Layout.fillWidth: true
                text: root.distributionName + "\n" + root.runningKernelLabel
                      + "\nKernel ready."
                color: root.textColor
                font.family: root.terminalFont
                font.pixelSize: root.loginFontSize
                lineHeight: 1.14
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.panelBorderColor
                opacity: 0.72
            }

            // Align labels and input baselines so the prompt reads like a
            // real getty while retaining a generous clickable text field.
            RowLayout {
                Layout.fillWidth: true
                spacing: root.compactLayout ? 8 : 12

                Text {
                    Layout.preferredWidth: root.compactLayout ? 112 : 138
                    text: "archlinux login:"
                    color: root.textColor
                    font.family: root.terminalFont
                    font.pixelSize: root.loginFontSize
                }

                TextField {
                    id: usernameField
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(30, root.loginFontSize * 1.85)
                    enabled: !root.loginPending
                    text: userModel.lastUser
                    placeholderText: "username"
                    placeholderTextColor: root.dimTextColor
                    color: root.textColor
                    cursorDelegate: terminalCursor
                    selectByMouse: true
                    font.family: root.terminalFont
                    font.pixelSize: root.loginFontSize
                    KeyNavigation.tab: passwordField
                    KeyNavigation.backtab: suspendButton
                    background: Rectangle {
                        color: usernameField.activeFocus ? "#120d2210" : "transparent"
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: usernameField.activeFocus ? 2 : 1
                            color: usernameField.activeFocus
                                   ? root.textColor : root.panelBorderColor
                            Behavior on color {
                                ColorAnimation { duration: 130 }
                            }
                        }
                    }
                    onAccepted: passwordField.forceActiveFocus()
                    onTextEdited: root.loginError = ""
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: root.compactLayout ? 8 : 12

                Text {
                    Layout.preferredWidth: root.compactLayout ? 112 : 138
                    text: "Password:"
                    color: root.textColor
                    font.family: root.terminalFont
                    font.pixelSize: root.loginFontSize
                }

                TextField {
                    id: passwordField
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(30, root.loginFontSize * 1.85)
                    enabled: !root.loginPending
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    placeholderText: "password"
                    placeholderTextColor: root.dimTextColor
                    color: root.textColor
                    cursorDelegate: terminalCursor
                    selectByMouse: true
                    font.family: root.terminalFont
                    font.pixelSize: root.loginFontSize
                    KeyNavigation.tab: sessionSelector
                    KeyNavigation.backtab: usernameField
                    background: Rectangle {
                        color: passwordField.activeFocus ? "#120d2210" : "transparent"
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: passwordField.activeFocus ? 2 : 1
                            color: passwordField.activeFocus
                                   ? root.textColor : root.panelBorderColor
                            Behavior on color {
                                ColorAnimation { duration: 130 }
                            }
                        }
                    }
                    onAccepted: root.submitLogin()
                    onTextEdited: root.loginError = ""
                }
            }

            // SDDM provides the model of installed desktop sessions. Qt's
            // standard ComboBox displays each model entry's documented name.
            RowLayout {
                Layout.fillWidth: true
                spacing: root.compactLayout ? 8 : 12

                Text {
                    Layout.preferredWidth: root.compactLayout ? 112 : 138
                    text: "Session:"
                    color: root.dimTextColor
                    font.family: root.terminalFont
                    font.pixelSize: root.detailFontSize
                }

                ComboBox {
                    id: sessionSelector
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(30, root.detailFontSize * 2.05)
                    enabled: !root.loginPending
                    model: sessionModel
                    textRole: "name"
                    currentIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
                    KeyNavigation.tab: loginButton
                    KeyNavigation.backtab: passwordField

                    contentItem: Text {
                        leftPadding: 10
                        rightPadding: sessionSelector.indicator.width + 8
                        text: sessionSelector.displayText || "No session available"
                        color: root.textColor
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                        font.family: root.terminalFont
                        font.pixelSize: root.detailFontSize
                    }

                    indicator: Text {
                        x: sessionSelector.width - width - 10
                        y: (sessionSelector.height - height) / 2
                        text: sessionSelector.popup.visible ? "▴" : "▾"
                        color: root.textColor
                        font.family: root.terminalFont
                        font.pixelSize: root.detailFontSize
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
                            font.pixelSize: root.detailFontSize
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
                Layout.topMargin: root.compactLayout ? 1 : 4
                spacing: root.compactLayout ? 8 : 10

                Button {
                    id: loginButton
                    Layout.preferredWidth: root.compactLayout ? 104 : 126
                    Layout.preferredHeight: Math.max(32, root.detailFontSize * 2.25)
                    enabled: !root.loginPending
                    text: root.loginPending ? "AUTH..." : "LOGIN"
                    onClicked: root.submitLogin()
                    KeyNavigation.tab: shutdownButton
                    KeyNavigation.backtab: sessionSelector
                    contentItem: Text {
                        text: loginButton.text
                        color: "#001500"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.family: root.terminalFont
                        font.pixelSize: root.detailFontSize
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
                    font.pixelSize: root.detailFontSize
                }
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.loginError
                color: "#ff9090"
                wrapMode: Text.Wrap
                font.family: root.terminalFont
                font.pixelSize: root.detailFontSize
            }
        }
    }

    // ----- Bottom terminal command bar ------------------------------------
    // Buttons stay visible even when unavailable; SDDM's capability flags
    // disable unsupported actions instead of implying they would work.
    Flow {
        id: commandBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.horizontalMargin
        anchors.rightMargin: root.horizontalMargin
        anchors.bottomMargin: root.verticalMargin
        spacing: root.compactLayout ? 7 : 18

        Button {
            id: shutdownButton
            width: root.compactLayout
                   ? Math.max(68, Math.floor((commandBar.width - commandBar.spacing * 2) / 3))
                   : 132
            height: root.compactLayout ? 30 : 34
            enabled: sddm.canPowerOff && !root.loginPending
            text: "[F1] Shutdown"
            onClicked: sddm.powerOff()
            KeyNavigation.tab: rebootButton
            KeyNavigation.backtab: loginButton
            contentItem: Text {
                text: shutdownButton.text
                color: shutdownButton.enabled ? root.textColor : root.dimTextColor
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.family: root.terminalFont
                font.pixelSize: root.detailFontSize
            }
            background: Rectangle {
                color: shutdownButton.down ? "#382b6e35" : "transparent"
                border.width: 1
                border.color: root.panelBorderColor
            }
        }

        Button {
            id: rebootButton
            width: root.compactLayout
                   ? Math.max(68, Math.floor((commandBar.width - commandBar.spacing * 2) / 3))
                   : 132
            height: root.compactLayout ? 30 : 34
            enabled: sddm.canReboot && !root.loginPending
            text: "[F2] Reboot"
            onClicked: sddm.reboot()
            KeyNavigation.tab: suspendButton
            KeyNavigation.backtab: shutdownButton
            contentItem: Text {
                text: rebootButton.text
                color: rebootButton.enabled ? root.textColor : root.dimTextColor
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.family: root.terminalFont
                font.pixelSize: root.detailFontSize
            }
            background: Rectangle {
                color: rebootButton.down ? "#382b6e35" : "transparent"
                border.width: 1
                border.color: root.panelBorderColor
            }
        }

        Button {
            id: suspendButton
            width: root.compactLayout
                   ? Math.max(68, Math.floor((commandBar.width - commandBar.spacing * 2) / 3))
                   : 132
            height: root.compactLayout ? 30 : 34
            enabled: sddm.canSuspend && !root.loginPending
            text: "[F3] Sleep"
            onClicked: sddm.suspend()
            KeyNavigation.tab: usernameField
            KeyNavigation.backtab: rebootButton
            contentItem: Text {
                text: suspendButton.text
                color: suspendButton.enabled ? root.textColor : root.dimTextColor
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.family: root.terminalFont
                font.pixelSize: root.detailFontSize
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
