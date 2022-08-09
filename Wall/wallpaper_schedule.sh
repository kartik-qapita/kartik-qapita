#! /usr/bin/env bash
#! /usr/bin/env zsh

sudo mkdir -p /usr/share/qapita

sudo apt install libglib2.0-dev-bin

wget -qO - https://github.com/PRATAP-KUMAR/ubuntu-gdm-set-background/archive/main.tar.gz | tar zx --strip-components=1 ubuntu-gdm-set-background-main/ubuntu-gdm-set-background

sudo wget https://raw.githubusercontent.com/kartik-qapita/kartik-qapita/main/wall.sh --output-document=/usr/share/qapita/wall.sh

sudo chmod +x /usr/share/qapita/wall.sh

sudo crontab -l > wallpaper                                                                        
echo "0 */1 * * * /usr/share/qapita/wall.sh >/dev/null 2>&1" >> wallpaper                            
sudo crontab wallpaper
