#!/usr/bin/env bash
wget https://raw.githubusercontent.com/kartik-qapita/kartik-qapita/main/Wall/Qapita.png -P ~/Documents
sqlite3 ~/Library/Application\ Support/Dock/desktoppicture.db "update data set value = '~/Documents/Qapita.png'";
killall Dock;
#osascript -e 'tell application "Finder" to set desktop picture to POSIX file "~/Downloads/Qapita.png"'
