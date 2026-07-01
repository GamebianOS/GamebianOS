/* Gamebian Calamares slideshow (based on Debian calamares-settings-debian show.qml). */

import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    Timer {
        interval: 20000
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Image {
            id: background1
            source: "slide1.png"
            width: 467; height: 280
            fillMode: Image.PreserveAspectFit
            anchors.centerIn: parent
        }
        Text {
            anchors.horizontalCenter: background1.horizontalCenter
            anchors.top: background1.bottom
            color: "#000000"
            text: qsTr("Welcome to Gamebian.<br/><br/>" +
                  "Connect this computer to the internet (Wi‑Fi or Ethernet on the panel). " +
                  "The installer needs a reachable mirror for package downloads (Calamares will not proceed without connectivity).<br/><br/>" +
                  "The rest of the installation is automated.")
            wrapMode: Text.WordWrap
            width: 600
            horizontalAlignment: Text.Center
        }
    }
}
