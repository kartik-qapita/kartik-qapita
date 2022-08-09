#! /usr/bin/env bash
#! /usr/bin/env zsh

echo "Wallpaper Setup"

sudo rm -rf /usr/share/backgrounds/Qapita.png

sudo wget https://raw.githubusercontent.com/kartik-qapita/kartik-qapita/main/Qapita.png -P /usr/share/backgrounds

gsettings set org.gnome.desktop.background picture-uri "file:////usr/share/backgrounds/Qapita.png"

sudo ./ubuntu-gdm-set-background --image /usr/share/backgrounds/Qapita.png