#! /usr/bin/env bash
#! /usr/bin/env zsh

#Creating a Dir for qapita 
sudo mkdir -p /usr/share/qapita

cd /usr/share/qapita

sudo wget https://raw.githubusercontent.com/kartik-qapita/kartik-qapita/main/Wall/wall.sh --output-document=/usr/share/qapita/wall.sh

sudo chmod +x /usr/share/qapita/wall.sh

bash /usr/share/qapita/wall.sh

cd 

sudo crontab -l > wallpaper

echo "0 */1 * * * /usr/share/qapita/wall.sh >/dev/null 2>&1" >> wallpaper

sudo crontab wallpaper
