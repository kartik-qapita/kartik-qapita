#! /usr/bin/env bash
#! /usr/bin/env zsh

sudo mkdir -p /usr/share/qapita

sudo wget https://github.com/kartik-qapita/kartik-qapita/blob/main/Wall.sh -P /usr/share/qapita

sudo chmod +x /usr/share/qapita/Wall.sh

sudo crontab -l > wallpaper                                                                        
echo "* 1 * * * /usr/share/qapita/Wall.sh >/dev/null 2>&1" >> wallpaper                            
sudo crontab wallpaper
