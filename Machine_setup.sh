#!/usr/bin/env bash
echo "QAPITA : 💻 MACHINE-SETUP"

set -euo pipefail

# some basic software
sudo apt install -y \
    openssh-server tmux git \
    build-essential \
    ca-certificates \
    apt-transport-https \
    curl wget \
    gnupg-agent \
    software-properties-common

sudo apt-get update && \
	sudo apt-get install -y curl wget tmux git groff less build-essential ca-certificates unzip lsb-release net-tools traceroute nmap tcpdump vim neovim telnet gnupg iputils-ping dnsutils gnupg2 postgresql-client

# Install required packages
sudo apt-get update && sudo apt-get install -y groff less

echo "ssh key"
if [ -d ~/.ssh ]
then
    echo "Directory .ssh exists."
else
    echo "Didnt find .ssh, Please generate ssh key and add it to GitHub as mentioned in machine-setup guide"
    exit
fi

#Installing VS Code
printf 'Do you wish to install VS Code (y/n)? '
read -r installcode

if [ "$installcode" != "${installcode#[Yy]}" ] ;then
  sudo apt-get install wget gpg
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
  sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
  sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
  rm -f packages.microsoft.gpg
  sudo apt update
  sudo apt install code
else
    echo "VS Code Installation skipped"
fi

#Installing Microsoft Teams
printf 'Do you wish to install Microsoft Teams (y/n)? '
read -r installteams

if [ "$installteams" != "${installteams#[Yy]}" ] ;then
  curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
  sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/ms-teams stable main" > /etc/apt/sources.list.d/teams.list'
  sudo apt update
  sudo apt install teams
else
    echo "Microsoft Teams Installation Skipped"
fi

# create folders for storing files required for setting up QapMap
mkdir -p ~/machine-setup/{certificates,eventstoredb,mongodb} ~/local/.bin

# Check if AWS CLI is already installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Installing..."
    
    # Download and install AWS CLI
    cd ~/machine-setup || exit
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    
    echo "AWS CLI has been installed."
else
    echo "AWS CLI is already installed."
fi

clear -x

#Configuring AWS_CREDENTIALS

echo "Enter You AWS Profile Name : (eg. qapita-yourname)"
read -r awsprofileconfigure

aws configure sso
export AWS_PROFILE=$awsprofileconfigure
export AWS_REGION=ap-south-1
aws s3 ls

printf 'Are the AWS S3 Buckets Listed above (y/n)? '
read -r awss3

if [ "$awss3" != "${awss3#[Yy]}" ] ;then
    echo "AWS Profile is configured"
else
    echo "AWS Profile Configuration not completed, please check the AWS SSO Configuration Guide"
    exit
fi

# copy files from qapita-development s3 bucket to ~/machine-setup

aws s3 cp s3://qapita-dev-development/machine-setup/certificates ~/machine-setup/certificates --recursive
aws s3 cp s3://qapita-dev-development/machine-setup/eventstoredb ~/machine-setup/eventstoredb --recursive
aws s3 cp s3://qapita-dev-development/machine-setup/mongodb ~/machine-setup/mongodb --recursive

export QAPITA_WORKSPACE=~/qapita-dev-workspace

cat << EOF >> ~/.bashrc
export PATH=~/.local/bin:\$PATH
export QAPITA_WORKSPACE=${QAPITA_WORKSPACE}
EOF

cat << EOF >> ~/.zshrc
export PATH=~/.local/bin:\$PATH
export QAPITA_WORKSPACE=${QAPITA_WORKSPACE}
EOF

echo set completion-ignore-case on | sudo tee -a /etc/inputrc
clear -x

# Configuring Git
echo "Enter Your Git-Hub Username"
read -r githubusername
git config --global user.name "$githubusername"

sleep 3
echo "Enter Your Qapita Email Id"
read -r qapitaemail
git config --global user.email "$qapitaemail"


# this is required for dotnet run or webpack to watch changes to files
sudo sysctl -w fs.inotify.max_user_instances=1024
sudo sysctl -w fs.inotify.max_user_watches=524288
sudo sysctl -p

# copy qapita-CA.crt (self generated root certificate) to the right folder
# this is required for https to work in local urls (https://qmap.qapitacorp.local, etc.)
sudo cp ~/machine-setup/certificates/qapita-CA.crt /usr/local/share/ca-certificates
sudo update-ca-certificates

# Update chrome to trust our root certificate

#chrome://settings/advanced
#    Manage Certificates
#    Authorities tab - select qapita-CA

EVENTSTORE_PACKAGE="EventStore-Commercial-Linux-v21.10.5.ubuntu-20.04.deb"
EVENTSTORE_INSTALL_PATH="$HOME/machine-setup/eventstoredb"
EVENTSTORE_CONFIG_PATH="/etc/eventstore"
EVENTSTORE_DATA_PATH="/eventstoredb-data"
EVENTSTORE_USER="eventstore"
EVENTSTORE_GROUP="eventstore"

check_installation() {
    if ! dpkg -s eventstore > /dev/null 2>&1; then
        install_eventstore
    else
        echo "EventStore is already installed."
    fi
}

install_eventstore() {
    echo "Installing EventStore..."
    sudo dpkg -i "$EVENTSTORE_INSTALL_PATH/$EVENTSTORE_PACKAGE"

    echo "Configuring EventStore..."
    sudo -u "$EVENTSTORE_USER" -g "$EVENTSTORE_GROUP" cp "$EVENTSTORE_INSTALL_PATH/eventstore.conf" "$EVENTSTORE_CONFIG_PATH"
    sudo -u "$EVENTSTORE_USER" -g "$EVENTSTORE_GROUP" cp "$EVENTSTORE_INSTALL_PATH/eventstore.pfx" "$EVENTSTORE_CONFIG_PATH"

    echo "Creating data directories..."
    sudo mkdir -p "$EVENTSTORE_DATA_PATH/{db,log}"
    sudo chown -R "$EVENTSTORE_USER:$EVENTSTORE_GROUP" "$EVENTSTORE_DATA_PATH"

    echo "Enabling and starting EventStore service..."
    sudo systemctl enable eventstore
    sudo systemctl start eventstore

    echo "EventStore installation and configuration completed."
}

check_installation
# the folder /eventstoredb-data/db should have the eventstore data

#Installing docker

# Check if Docker is already installed
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Proceeding with installation..."

    # Update package information and install required tools
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends ca-certificates curl gnupg

    # Download and add Docker GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update and install Docker packages
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io

    # Add user to the docker group
    sudo usermod -aG docker "$USER"

    echo "Docker installation completed. Please log out and log back in for group membership to take effect."

    # Configure Docker to start on boot with systemd
    sudo systemctl enable docker.service
    sudo systemctl enable containerd.service

    echo "Docker has been configured to start on boot with systemd."

else
    echo "Docker is already installed."
fi

# Installing MongoDB
# Function to install MongoDB
install_mongodb() {
    # Install prerequisites
    sudo apt-get update
    sudo apt-get install -y gnupg curl

    # Import MongoDB GPG key
    curl -fsSL https://pgp.mongodb.com/server-7.0.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor

    # Add MongoDB repository to sources list
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $VERSION_CODENAME/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list

    # Install MongoDB
    sudo apt-get update
    sudo apt-get install -y mongodb-org

    # Create data and log directories
    sudo mkdir -p /mongodb-data/{db,log}
    sudo chown -R mongodb:mongodb /mongodb-data

    # Replace MongoDB configuration file
    sudo cp ~/machine-setup/mongodb/mongod.conf /etc

    # Start MongoDB service
    sudo systemctl start mongod
    sudo systemctl status mongod

    # Enable MongoDB to start on system reboot
    sudo systemctl enable mongod

    echo "MongoDB installation completed."
}

# Check if MongoDB is already installed
if dpkg -l | grep -q "mongodb-org"; then
    echo "MongoDB is already installed."
else
    # Check OS release version
    source /etc/os-release

    if [[ "$ID" == "ubuntu" ]]; then
        if [[ "$VERSION_ID" == "22.04" || "$VERSION_ID" == "20.04" ]]; then
            echo "Supported Ubuntu version: $VERSION_ID"
            install_mongodb
        else
            echo "Unsupported Ubuntu version: $VERSION_ID. Only Ubuntu 20.04 LTS and 22.04 LTS are supported."
        fi
    else
        echo "This script is designed for Ubuntu only."
    fi
fi


# Install .NET
# Function to install dotnet on Ubuntu 22.04 LTS
install_dotnet_2204() {
    sudo apt-get update && \
    sudo apt-get install -y dotnet-sdk-7.0

    sudo apt-get update && \
    sudo apt-get install -y aspnetcore-runtime-7.0
}

# Function to install dotnet on Ubuntu 20.04 LTS
install_dotnet_2004() {
    wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    sudo dpkg -i packages-microsoft-prod.deb

    sudo apt-get update && \
    sudo apt-get install -y dotnet-sdk-7.0

    sudo apt-get update && \
    sudo apt-get install -y aspnetcore-runtime-7.0
}

# Check OS release version
source /etc/os-release

if [[ "$ID" == "ubuntu" ]]; then
    case "$VERSION_CODENAME" in
        "jammy") # Ubuntu 22.04 LTS
            install_dotnet_2204
            ;;
        "focal") # Ubuntu 20.04 LTS
            install_dotnet_2004
            ;;
        *)
            echo "Unsupported Ubuntu version."
            exit 1
            ;;
    esac
else
    echo "This script is intended for Ubuntu only."
    exit 1
fi

# Install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.4/install.sh | bash

export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm

nvm --version

# Install node
export NODE_LTS=`nvm ls-remote --lts | tail -n 1 | awk 'BEGIN{FS=" "} {print $1}'`
nvm install ${NODE_LTS}
nvm alias default ${NODE_LTS}
nvm use ${NODE_LTS}
npm install -g lerna typescript concurrently

# zsh issues - Make sure nvm is configured for zsh as well
cat << EOF >> ~/.zshrc
export NVM_DIR="$HOME/.nvm"                                                                                                                                     [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
nvm --version
  # This loads nvm
EOF

#Installing Seq
sudo docker image pull datalust/seq

mkdir -p ${QAPITA_WORKSPACE}/data/seq

sudo docker container create -p 5341:5341 -p 8081:80 \
    -v ${QAPITA_WORKSPACE}/data/seq:/data \
    -e ACCEPT_EULA=Y \
    --name q-seq-node datalust/seq

sudo docker container start q-seq-node
sudo docker container update --restart always q-seq-node

# Installing NGINX 

# Check if NGINX is already installed
if [ -x "$(command -v nginx)" ]; then
    echo "NGINX is already installed."
    exit 0
fi

# Install prerequisites
sudo apt update
sudo apt install -y curl gnupg2 ca-certificates lsb-release ubuntu-keyring

# Import the official NGINX signing key
curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null

# Verify the key fingerprint
expected_fingerprint="573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62"
actual_fingerprint=$(gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg | grep -oP '(?<=\[\w\]\s+)\w+')
if [ "$actual_fingerprint" != "$expected_fingerprint" ]; then
    echo "Key fingerprint does not match. Removing the keyring file."
    sudo rm /usr/share/keyrings/nginx-archive-keyring.gpg
    exit 1
fi

# Set up the apt repository
release_codename=$(lsb_release -cs)
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/stable/ubuntu $release_codename nginx" | sudo tee /etc/apt/sources.list.d/nginx.list

# Set up repository pinning
echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx

# Install NGINX
sudo apt update
sudo apt install -y nginx

echo "NGINX has been installed successfully."

# /etc/hosts
# we need to add a few lines in /etc/hosts
echo '127.0.0.1   auth.qapitacorp.local
127.0.0.1   qmap.qapitacorp.local
127.0.0.1   captable.qapitacorp.local
127.0.0.1   seq.qapitacorp.local
127.0.0.1   eventstore.qapitacorp.local' | sudo tee -a /etc/hosts > /dev/null

# configure nginx to reverse proxy to our local services

if [ -d "/etc/nginx/sites-available" ] && [ -d "/etc/nginx/sites-enabled" ];
then
    sudo cp ~/machine-setup/certificates/qapitacorp.local /etc/nginx/sites-available
    sudo ln -s /etc/nginx/sites-available/qapitacorp.local /etc/nginx/sites-enabled/qapitacorp.local
else
    sudo mkdir -p /etc/nginx/{sites-available,sites-enabled}
    sudo cp ~/machine-setup/certificates/qapitacorp.local /etc/nginx/sites-available
    sudo ln -s /etc/nginx/sites-available/qapitacorp.local /etc/nginx/sites-enabled/qapitacorp.local
fi

sudo mkdir -p /etc/ssl/certs /etc/ssl/private

sudo cp ~/machine-setup/certificates/qapitacorp.local.key /etc/ssl/private
sudo cp ~/machine-setup/certificates/qapitacorp.local-bundle.crt /etc/ssl/certs
sudo chmod 600 /etc/ssl/private/qapitacorp.local.key

# restart nginx so that our changes are reflected
sudo systemctl restart nginx

# Creating SWAP Memory
# Function to create swap memory
create_swap_memory() {
    echo "Creating swapfile"
    read -rp "Enter the size of swap needed (e.g., 16 for 16GB of swap): " swap_size

    sudo fallocate -l "${swap_size}G" /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab
}

# Main script
read -rp "(Optional) - Do you wish to create SWAP Memory? (y/n): " createswap

if [[ $createswap =~ ^[Yy]$ ]]; then
    create_swap_memory
else
    echo "Swap Memory Creation Skipped"
fi

#Cloning Server & client
export QAPITA_WORKSPACE=~/qapita-dev-workspace

PS3='Please select any option to clone project to your local: '
options=("QapMap" "QapMatch" "Liquidity" "Open-Marketplace" "QFund" "Quit")
select opt in "${options[@]}"
do
    case $opt in
        "QapMap")
            echo "Cloning the $opt Project Repos"
            # Clone the server repository and restore nuget packages
            git clone git@github.com:qapita/captable-writemodel.git ${QAPITA_WORKSPACE}/qmap/server
            cd ${QAPITA_WORKSPACE}/qmap/server/
            #Replace Default value with Generated Nuget Key in nuget.config
            echo "ENTER YOUR NUGET KEY"
            read nugetkey
            sed -i 's/%NUGET_SECRET_ACCESS_KEY%/\'$nugetkey'/' nuget.config
            pushd ${QAPITA_WORKSPACE}/qmap/server/src/WebAPI && dotnet restore && popd
            pushd ${QAPITA_WORKSPACE}/qmap/server/src/IDP && dotnet restore && popd
            pushd ${QAPITA_WORKSPACE}/qmap/server/src/WebConsole && dotnet restore && popd
            pushd ${QAPITA_WORKSPACE}/qmap/server/src/Qapita.QMap.UserTaskManagement && dotnet restore && popd
            cd ${QAPITA_WORKSPACE}/qmap/server/src/IDP
            cp appsettings.Development.Template.json appsettings.Development.json
            dotnet run /seed
            cd ${QAPITA_WORKSPACE}/qmap/server/src/WebAPI
            cp appsettings.Development.template.json appsettings.Development.json
            cd ${QAPITA_WORKSPACE}/qmap/server/src/Qapita.QMap.UserTaskManagement
            cp appsettings.Development.Template.json appsettings.Development.json
            cd ${QAPITA_WORKSPACE}/qmap/server/src/WebConsole
            cp appsettings.Development.Template.json appsettings.Development.json
            #client
            git clone git@github.com:qapita/captable-web.git ${QAPITA_WORKSPACE}/qmap/client
            sudo apt install -y build-essential
            pushd ${QAPITA_WORKSPACE}/qmap/client && lerna bootstrap && popd
            pushd ${QAPITA_WORKSPACE}/qmap/client/packages/web
            npm rebuild node-sass
            echo "Installing yarn globally"
            npm install --global yarn
            echo "Your yarn version is"
            yarn --version
            echo "Changing Directory to client"
            cd ${QAPITA_WORKSPACE}/qmap/client
            echo "Removing node_modules..."
            yes | lerna clean
            echo "Removing node_modules inside client"
            rm -rf node_modules
            echo "Unlinking all symlinks"
            yarn unlink-all
            echo "Linking all symlinks"
            yarn link-all
            echo "Changing to web package"
            cd packages/web
            ;;
        "QapMatch")
            echo "Cloning the $opt Project Repos"
            git clone git@github.com:qapita/qmatch-org-liquidity-event.git ${QAPITA_WORKSPACE}/qapmatch/server
            cd ${QAPITA_WORKSPACE}/qapmatch/server/
            echo "ENTER YOUR NUGET KEY"
            read nugetkey
            sed -i 's/%NUGET_SECRET_ACCESS_KEY%/\'$nugetkey'/' nuget.config
            pushd ${QAPITA_WORKSPACE}/qapmatch/server/src/WebAPI && dotnet restore && popd
            pushd ${QAPITA_WORKSPACE}/qapmatch/server/src/Application && dotnet restore && popd
            pushd ${QAPITA_WORKSPACE}/qapmatch/server/src/Infrastructure && dotnet restore && popd
            pushd ${QAPITA_WORKSPACE}/qapmatch/server/src/Domain && dotnet restore && popd
            cd ${QAPITA_WORKSPACE}/qmap/server/src/WebAPI
            cp appsettings.Development.Template.json appsettings.Development.json
            #client
            git clone git@github.com:qapita/qapmatch-client.git ${QAPITA_WORKSPACE}/qapmatch/client
            ;;
        "Liquidity")
            echo "Cloning the $opt Project Repos"
            git clone git@github.com:qapita/qap-liquidity-server.git ${QAPITA_WORKSPACE}/liquidity/server
            cd ${QAPITA_WORKSPACE}/liquidity/server/
            echo "ENTER YOUR NUGET KEY"
            read nugetkey
            sed -i 's/%NUGET_SECRET_ACCESS_KEY%/\'$nugetkey'/' nuget.config
            #client
            git clone git@github.com:qapita/qap-liquidity-client.git ${QAPITA_WORKSPACE}/liquidity/client
            ;;
        "Open-Marketplace")
            echo "Cloning the $opt Project Repos"
            git clone git@github.com:qapita/qap-match-open.server.git ${QAPITA_WORKSPACE}/open-marketplace/server
            cd ${QAPITA_WORKSPACE}/open-marketplace/server/
            echo "ENTER YOUR NUGET KEY"
            read nugetkey
            sed -i 's/%NUGET_SECRET_ACCESS_KEY%/\'$nugetkey'/' nuget.config
            pushd ${QAPITA_WORKSPACE}/open-marketplace/server/src/WebAPI && dotnet restore && popd
            pushd ${QAPITA_WORKSPACE}/open-marketplace/server/src/Application && dotnet restore && popd
            pushd ${QAPITA_WORKSPACE}/open-marketplace/server/src/Infrastructure && dotnet restore && popd
            pushd ${QAPITA_WORKSPACE}/open-marketplace/server/src/Domain && dotnet restore && popd
            pushd ${QAPITA_WORKSPACE}/open-marketplace/server/src/Seedwork && dotnet restore && popd
            cd ${QAPITA_WORKSPACE}/qmap/server/src/WebAPI
            cp appsettings.Development.Template.json appsettings.Development.json
            #client
            git clone git@github.com:qapita/qap-match-open.client.git ${QAPITA_WORKSPACE}/open-marketplace/client
            ;;
        "QFund")
            echo "Cloning the $opt Project Repos"
            git clone git@github.com:qapita/qap-fund-mgmt-server.git ${QAPITA_WORKSPACE}/qfund/server
            cd ${QAPITA_WORKSPACE}/open-marketplace/server/
            echo "ENTER YOUR NUGET KEY"
            read nugetkey
            sed -i 's/%NUGET_SECRET_ACCESS_KEY%/\'$nugetkey'/' nuget.config
            #client
            git clone git@github.com:qapita/qap-fund-mgmt-client.git ${QAPITA_WORKSPACE}/qfund/client
            ;;
        "Quit")
            break
            ;;
        *) echo "invalid option $REPLY";;
    esac
done

clear -x

echo "Installed - AWS-cli , Git, Eventstore, Mongodb, Docker, Nginx, Dotnet, Node, SEQ"

echo '

                       ___      _    ____ ___ _____  _    
                      / _ \    / \  |  _ \_ _|_   _|/ \   
                     | | | |  / _ \ | |_) | |  | | / _ \  
                     | |_| | / ___ \|  __/| |  | |/ ___ \ 
                      \__\_\/_/   \_\_|  |___| |_/_/   \_\
                                                          
                                                          
'
echo ">> 🎉 Machine-Setup 💻 Completed <<"
