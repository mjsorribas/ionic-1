import QtQuick 1.1
import com.pipacs.ionic.IWebView 1.0
import com.pipacs.ionic.Book 1.0
import com.pipacs.ionic.Preferences 1.0
import "theme.js" as Theme

Flickable {
    id: flickable

    // Target reading position, within the current part of the book. After loading the part, BookView will jump to this position, unless it is set to -1
    property double targetPos: -1

    // Target reading anchor, within the current part of the book. After loading the part, BookView will jump to this anchor, unless it is set to ""
    property string targetAnchor: ""

    // Current part index
    property int part: 0

    property alias url: webView.url
    property alias sx: flickable.contentX
    property alias sy: flickable.contentY
    property alias webView: webView
    property alias updateTimer: updateTimer

    signal loadStarted
    signal loadFinished
    signal loadFailed

    contentWidth: Math.max(parent.width, webView.width)
    contentHeight: Math.max(parent.height, webView.height)
    anchors.fill: parent
    pressDelay: 30
    flickableDirection: Flickable.VerticalFlick
    interactive: prefs.useSwipe
    focus: true

    IWebView { // WebView...
        id: webView
        settings.standardFontFamily: prefs.font
        settings.defaultFontSize: ((platform.osName == "harmattan")? 26: 22) + (prefs.zoom - 100) / 10
        settings.minimumFontSize: (platform.osName == "harmattan")? 22: 18
        settings.javascriptEnabled: true
        settings.javaEnabled: false
        settings.javascriptCanOpenWindows: false
        settings.localContentCanAccessRemoteUrls: false
        settings.offlineStorageDatabaseEnabled: false
        settings.offlineWebApplicationCacheEnabled: false
        settings.pluginsEnabled: false
        preferredWidth: flickable.width
        preferredHeight: flickable.height
        contentsScale: 1
        z: 0

        property bool loading: false

        // Jump to the target position after a slight delay
        Timer {
            id: jumpTimer
            interval: 10
            running: false
            repeat: false
            onTriggered: jump()
        }

        onLoadFailed: {
            loading = false
            flickable.targetPos = -1
            flickable.targetAnchor = ""
            coverRemover.restart()
        }

        onLoadFinished: {
            setStyle(prefs.style)
            setMargin(prefs.margin)
            loading = false
            jumpTimer.start()
            coverRemover.restart()
        }

        onLoadStarted: loading = true

        // Forward signals
        Component.onCompleted: {
            loadStarted.connect(flickable.loadStarted)
            loadFailed.connect(flickable.loadFailed)
            loadFinished.connect(flickable.loadFinished)
            linkClicked.connect(flickable.goToUrl)
        }
    }

    // Show bookmarks, using the bookmark list as model
    Repeater {
        z: 1
        model: library.nowReading.bookmarks
        delegate: bookmarkDelegate
    }

    // Hide cover with a delay (prevent flicking)
    Timer {
        id: coverRemover
        interval: 200
        running: false
        repeat: false
        onTriggered: styleCover.opacity = 0
    }

    // Delegate to draw a bookmark, but only if it points to the current part
    Component {
        id: bookmarkDelegate
        Item {
            Image {
                id: star
                x: webView.width - 50
                y: webView.contentsSize.height * library.nowReading.bookmarks[index].position
                width: 50
                height: 50
                visible: !webView.loading && (library.nowReading.bookmarks[index].part === flickable.part)
                source: "qrc:/icons/star.png"
                opacity: 0.75
            }
            MouseArea {
                anchors.fill: star
                enabled: star.visible
                onPressAndHold: {
                    console.log("* Bookmark image press-and-hold")
                }
            }
        }
    }

    // A rectangle to cover up the web view while it is loading
    Rectangle {
        id: styleCover
        anchors.fill: parent
        border.width: 0
        color: Theme.background(prefs.style)
        z: 1
    }

    // Periodically update last reading position
    Timer {
        id: updateTimer
        interval: 3000
        running: true
        repeat: true
        onTriggered: {if (!webView.loading) updateLastBookmark()}
    }

    // Scroll up one page
    function goToPreviousPage() {
        if (flickable.contentY == 0) {
            goToPreviousPart()
            return
        }
        var newY = flickable.contentY - flickable.height + 17;
        if (newY < 0) {
            newY = 0
        }
        flickable.contentY = newY
        updateLastBookmark()
    }

    // Scroll down one page
    function goToNextPage() {
        if (flickable.contentY + flickable.height >= webView.contentsSize.height) {
            goToNextPart()
            return
        }
        var newY = flickable.contentY + flickable.height - 17;
        if (newY + flickable.height > webView.contentsSize.height) {
            newY = webView.contentsSize.height - flickable.height
        }
        flickable.contentY = newY
        updateLastBookmark()
    }

    // Load previous part
    function goToPreviousPart() {
        if (flickable.part == 0) {
            return
        }
        flickable.part -= 1
        flickable.targetPos = 1
        load(library.nowReading.urlFromPart(flickable.part))
    }

    // Load next part
    function goToNextPart() {
        if (flickable.part >= (library.nowReading.partCount - 1)) {
            return;
        }
        flickable.part += 1
        flickable.targetPos = 0
        load(library.nowReading.urlFromPart(flickable.part))
    }

    // Go to any URL in the book
    function goToUrl(link) {
        console.log("* BookView.flickable.goToUrl " + link)
        var linkStr = new String(link)
        var part = library.nowReading.partFromUrl(linkStr)
        console.log("*  Part " + part)
        if (part < 0) {
            if (prefs.openExternal) {
                console.log("*  Opening external URL")
                Qt.openUrlExternally(link)
            }
            return
        }
        flickable.targetAnchor = ""
        var hashPos = linkStr.lastIndexOf("#")
        if (hashPos >= 0) {
            flickable.targetAnchor = linkStr.substring(hashPos + 1)
            linkStr = linkStr.substring(0, hashPos)
            console.log("*  Anchor " + flickable.targetAnchor)
        }
        if (part != flickable.part) {
            console.log("*  Loading new part " + part + ", current is " + flickable.part)
            flickable.part = part
            load(linkStr)
        } else {
            jump()
        }
    }

    // Update book's last reading position, but only if it has been changed
    function updateLastBookmark() {
        if (webView.contentsSize.height > 0) {
            var currentPosition = flickable.contentY / webView.contentsSize.height
            var book = library.nowReading
            if ((Math.abs(book.lastBookmark.position - currentPosition) > 0.0005) || (book.lastBookmark.part != flickable.part)) {
                book.setLastBookmark(flickable.part, currentPosition)
                book.save()
            }
        }
    }

    // Jump to a new location within the page, specified in flickable.targetPos or flickable.targetAnchor
    function jump() {
        if (flickable.targetPos != -1) {
            console.log("* BookView.jump: To position " + flickable.targetPos)
            var newY = webView.contentsSize.height * flickable.targetPos
            if (flickable.targetPos == 1) {
                newY -= flickable.height
            }
            if (newY < 0) {
                newY = 0
            }
            flickable.contentY = newY
            flickable.targetPos = -1
            updateLastBookmark()
        } else if (flickable.targetAnchor != "") {
            console.log("* BookView.jump: To anchor " + flickable.targetAnchor)
            // NOTE: We can't use document.location.hash because the viewport is as big as the whole page
            // var script = "window.location.hash = \"" + flickable.targetAnchor + "\""
            var script = "document.getElementById('" + flickable.targetAnchor + "').getBoundingClientRect().top"
            console.log("*  " + script)
            var ret = webView.evaluateJavaScript(script)
            console.log("*  --> " + ret)
            flickable.contentY = 0 + ret
            flickable.targetAnchor = ""
            updateLastBookmark()
        }
    }

    // Set style
    function setStyle(style) {
        styleCover.color = Theme.background(style)
        webView.evaluateJavaScript(Theme.webTheme(style))
    }

    // Set body margins
    function setMargin(margin) {
        webView.evaluateJavaScript("document.body.style.margin = '" + prefs.margin + "px " + prefs.margin + "px " + prefs.margin + "px " + prefs.margin + "px'")
    }

    // Load URL while covering the web view
    function load(link) {
        console.log("* BookView.load: " + link)
        styleCover.opacity = 1
        webView.url = "" + link
    }
}
