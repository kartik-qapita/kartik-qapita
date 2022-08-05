#! /usr/bin/env bash
#! /usr/bin/env zsh

sudo mkdir -p /usr/share/qapita

sudo wget https://raw.githubusercontent.com/kartik-qapita/kartik-qapita/main/Wall.sh --output-document=/usr/share/qapita/Wall.sh

sudo chmod +x /usr/share/qapita/Wall.sh

sudo crontab -l > wallpaper                                                                        
echo "* * * * * /usr/share/qapita/Wall.sh >/dev/null 2>&1" >> wallpaper                            
sudo crontab wallpaper
