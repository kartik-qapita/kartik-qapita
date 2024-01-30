#!/bin/bash

echo "QAPITA : 💻 MACHINE-SETUP"
LOG_FILE="/var/log/qapita_local_machine_setup_script.log" # Set the path for the log file

# Logging function
log() {
    local message="$1"
    local level="${2:-INFO}"
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" | sudo tee -a "$LOG_FILE"
}

# Function for logging errors
log_error() {
    log "$1" "ERROR"
}

# Function for logging warnings
log_warning() {
    log "$1" "WARNING"
}

# Function for modularized package installation
install_package() {
    local package_name="$1"
    local package_url="${2:-}"

    if dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -q "ok installed"; then
        log "$package_name is already installed."
        return 0
    fi

    log "Installing $package_name..."
    sudo apt-get update
    if [ -z "$package_url" ]; then
        sudo apt-get install -y "$package_name"
    else
        install_package_from_url "$package_url"
    fi
}

# Function for modularized package installation from URL
install_package_from_url() {
    local url="$1"
    local package_name="${url##*/}"
    local download_path="/tmp/$package_name"

    if [ ! -e "$download_path" ]; then
        log "Downloading $package_name..."
        curl -o "$download_path" -sSL "$url"
    fi

    if ! dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -q "ok installed"; then
        log "Installing $package_name..."
        sudo dpkg -i "$download_path"
        sudo apt-get install -f -y
    else
        log "$package_name is already installed."
    fi

    rm -f "$download_path"
}

check_configure_ssh_key() {
    if [ ! -f ~/.ssh/id_rsa ]; then
        echo "No SSH key found. Let's configure one."
        read -rp "Enter your email address for the SSH key: " email
        read -rsp "Enter a passphrase for the SSH key: " passphrase
        echo
        ssh-keygen -t rsa -b 4096 -C "$email" -N "$passphrase"
        eval "$(ssh-agent -s)"
        ssh-add ~/.ssh/id_rsa
        echo "SSH key has been generated and added to the SSH agent."
        echo "Please copy the following public key and add it to your GitHub account settings:"
        cat ~/.ssh/id_rsa.pub
    else
        echo "SSH key is already configured."
    fi
}

configure_github_credentials() {
    log "Configuring GitHub credentials..."
    existing_username=$(git config --global user.name)
    existing_email=$(git config --global user.email)

    if [[ -n "$existing_username" && -n "$existing_email" ]]; then
        echo "GitHub credentials are already configured:"
        echo "GitHub Username: $existing_username"
        echo "GitHub Email: $existing_email"
    else
        read -rp "Enter your GitHub username: " github_username
        read -rp "Enter your Qapita email address: " github_email

        echo "GitHub Username: $github_username"
        echo "GitHub Email: $github_email"

        read -rp "Is this information correct? (y/n): " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            git config --global user.name "$github_username"
            git config --global user.email "$github_email"
            log "GitHub credentials configured successfully."
        else
            log "GitHub credentials configuration canceled."
        fi
    fi
}

install_aws_cli() {
    log "Downloading AWS CLI..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

    log "Unzipping AWS CLI..."
    unzip awscliv2.zip

    log "Installing AWS CLI..."
    sudo ./aws/install

    log "Cleaning up..."
    rm -r awscliv2.zip aws
}

configure_aws_sso() {
    echo "Please confirm that you have AWS access using AWS SSO."
    read -rp "Have you logged in to AWS SSO and confirmed your access? (yes/no): " aws_access_confirmed

    if [ "$aws_access_confirmed" = "yes" ]; then
        read -rp "Enter your AWS SSO profile name (e.g., qapita-yourname): " profile_name
        aws configure sso
        export AWS_PROFILE="$profile_name"
        export AWS_REGION=ap-south-1

        aws s3 ls
        aws sts get-caller-identity | jq
        echo "AWS SSO configuration has been completed."
    else
        echo "AWS access is required to proceed with AWS SSO configuration."
    fi
}

# Function for checking and installing Node.js with NVM
install_nodejs_with_nvm() {
    # Check if nvm is installed
    if ! command -v nvm &>/dev/null; then
        # Install nvm
        log "Installing NVM..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.4/install.sh | bash
        if [ -z "${XDG_CONFIG_HOME-}" ]; then
            NVM_DIR="${HOME}/.nvm"
        else
            NVM_DIR="${XDG_CONFIG_HOME}/nvm"
        fi
        export NVM_DIR

        if [ -s "$NVM_DIR/nvm.sh" ]; then
            . "$NVM_DIR/nvm.sh" # This loads nvm
        fi

        source "$HOME/.bashrc"

        log "NVM has been installed."
    fi

    if ! command -v nvm &>/dev/null; then
        log_warning "nvm not found. Skipping Node.js installation."
        return
    fi

    if ! nvm list | grep -q 'N/A'; then
        log "Node.js is already installed with nvm."
        return
    fi

    log "Installing Node.js with nvm..."

    if ! command -v node &>/dev/null; then
        NODE_LTS=$(nvm ls-remote --lts | tail -n 1 | awk 'BEGIN{FS=" "} {print $1}')
        nvm install "$NODE_LTS"
        nvm alias default "$NODE_LTS"
        nvm use "$NODE_LTS"
        else
        log "Node.js is already installed with nvm."
    fi
    if ! command -v npm &>/dev/null; then
        npm install -g lerna typescript concurrently
    fi
    log "Node.js has been successfully installed."
}

# Function for installing .NET based on Ubuntu version
install_dotnet() {
    local VERSION_CODENAME
    VERSION_CODENAME=$(lsb_release -cs)

    log "version codename: $VERSION_CODENAME"
    log "Installing .NET..."
    case "$VERSION_CODENAME" in
    "jammy")
        install_package dotnet-sdk-7.0
        install_package aspnetcore-runtime-7.0

        log ".NET installation completed."
        ;;
    "focal")
        install_package_from_url "https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb"
        install_package dotnet-sdk-7.0
        install_package aspnetcore-runtime-7.0

        log ".NET installation completed."
        ;;
    *)
        log "Unsupported Ubuntu version."
        exit 1
        ;;
    esac
}

#Funtion for installing Docker
install_docker() {
    log "Installing Docker..."
    local VERSION_CODENAME
    VERSION_CODENAME=$(lsb_release -cs)

    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" |
        sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

    install_package docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    sudo groupadd docker
    sudo usermod -aG docker "$USER"
    newgrp docker
    sudo chown "$USER":"$USER" /home/"$USER"/.docker -R
    sudo chmod g+rwx "$HOME/.docker" -R
    sudo systemctl enable docker.service
    sudo systemctl enable containerd.service
    sudo systemctl start docker
    log "Docker installation completed."
}

# Function for installing MongoDB
install_mongodb() {
    local mongodb_data_dir="/mongodb-data" # Directory for MongoDB data storage
    local version_codename
    version_codename="$(lsb_release -cs)"

    log "Installing MongoDB..."

    if [ "$version_codename" == "jammy" ]; then
        curl -fsSL https://pgp.mongodb.com/server-7.0.asc | sudo gpg -o /etc/apt/trusted.gpg.d/mongodb-server-7.0.gpg --dearmor
        echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
    elif [ "$version_codename" == "focal" ]; then
        curl -fsSL https://pgp.mongodb.com/server-7.0.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
        echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
    else
        log "Unsupported Ubuntu version."
        exit 1
    fi

    # Update and install MongoDB
    sudo apt-get update
    sudo apt-get install -y mongodb-org

    # Create data and log directories
    sudo mkdir -p "${mongodb_data_dir}/"{db,log}

    # Set ownership for MongoDB data directory
    sudo chown -R mongodb:mongodb "${mongodb_data_dir}"

    # Start MongoDB service and enable on system reboot
    sudo systemctl start mongod
    sudo systemctl status mongod
    sudo systemctl enable mongod

    log "MongoDB installation completed."
}

install_eventstore() {
    log "Installing EventStore..."

    local ubuntu_version
    ubuntu_version="$(lsb_release -rs)"

    if [ "$ubuntu_version" = "20.04" ]; then
        package_name="EventStore-Commercial-Linux-v22.10.4.ubuntu-20.04.deb"
    elif [ "$ubuntu_version" = "22.04" ]; then
        package_name="EventStore-Commercial-Linux-v22.10.4.ubuntu-22.04.deb"
    else
        echo "Unsupported Ubuntu version: $ubuntu_version"
        return 1
    fi

    package_path="$HOME/machine-setup/eventstoredb/$package_name"
    echo "Installing EventStore from $package_path..."
    sudo dpkg -i "$package_path"

    echo "Configuring EventStore..."
    sudo -u eventstore -g eventstore cp ~/machine-setup/eventstoredb/eventstore.conf /etc/eventstore
    sudo -u eventstore -g eventstore cp ~/machine-setup/eventstoredb/eventstore.pfx /etc/eventstore

    echo "Creating data directories..."
    sudo mkdir -p "/eventstoredb-data/{db,log}"
    sudo chown -R eventstore:eventstore /eventstoredb-data/

    echo "Enabling and starting EventStore service..."
    sudo systemctl enable eventstore
    sudo systemctl start eventstore

    log "EventStore installation completed."
}

install_nginx() {
    log "Installing Nginx..."

    # Install prerequisites
    sudo apt install -y curl gnupg2 ca-certificates lsb-release ubuntu-keyring

    # Fetch and import the nginx signing key
    curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null

    # Verify the key fingerprint
    expected_fingerprint="573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62"
    actual_fingerprint=$(gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg | awk '/^pub/{getline; print}' | awk '{print $1}')

    if [ "$actual_fingerprint" != "$expected_fingerprint" ]; then
        echo "Key fingerprint verification failed. Removing the key."
        sudo rm /usr/share/keyrings/nginx-archive-keyring.gpg
        return 1
    fi

    # Set up the apt repository for nginx
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" | sudo tee /etc/apt/sources.list.d/nginx.list

    # Set up repository pinning
    echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx

    # Install nginx
    install_package nginx

    log "Nginx installation completed."
}

# Function for installing PostgreSQL
install_postgresql() {
    log "Installing PostgreSQL..."

    if ! command -v psql &>/dev/null; then
        # Install necessary packages
        sudo apt install -y curl ca-certificates

        # Import PostgreSQL GPG key
        sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --create-dirs --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc

        # Add PostgreSQL repository and update
        sudo sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

        # Install PostgreSQL
        install_package postgresql-15
        log "PostgreSQL installation completed."
    else
        log "PostgreSQL is already installed."
    fi
}

# Function to create swap memory
create_swap_memory() {
    log "Swap Memory Creation"
    read -rp "Enter the size of swap needed (e.g., 16 for 16GB of swap): " swap_size
    if [[ ! "$swap_size" =~ ^[0-9]+$ ]]; then
        log_error "Invalid input. Please enter a numeric value."
        return 1
    fi

    log "Creating a swap file of ${swap_size}GB..."
    sudo fallocate -l "${swap_size}G" /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab

    log "Swap memory of ${swap_size}GB has been created."
}

# Main setup
log "Starting setup..."

# Install essential packages
essential_packages=(
    "curl"
    "wget"
    "tmux"
    "git"
    "groff"
    "less"
    "build-essential"
    "ca-certificates"
    "unzip"
    "lsb-release"
    "net-tools"
    "traceroute"
    "nmap"
    "tcpdump"
    "vim"
    "telnet"
    "gnupg"
    "iputils-ping"
    "dnsutils"
    "gnupg2"
    "postgresql-client"
    "openssh-server"
    "apt-transport-https"
    "gnupg-agent"
    "shellcheck"
    "software-properties-common"
    "fonts-liberation" "libasound2" "libatk-bridge2.0-0" "libatk1.0-0" "libatspi2.0-0" "libdrm2" "libgbm1" "libgtk-3-0" "libnspr4" "libnss3" "libu2f-udev" "libvulkan1" "libxcomposite1" "libxdamage1" "libxfixes3" "libxkbcommon0" "libxrandr2" "xdg-utils" "libnotify4" "libsecret-1-0" "libsecret-common" "apt-utils"
)

for package in "${essential_packages[@]}"; do
    install_package "$package"
done

clear -x

check_configure_ssh_key

clear -x

#configure_github_credentials

if ! command -v aws &>/dev/null; then
    install_aws_cli
else
    log "AWS CLI is already installed."
fi

configure_aws_sso

# create folders for storing files required for setting up the environment
mkdir -p ~/machine-setup/{certificates,eventstoredb,mongodb} ~/local/.bin

# copy files from qapita-dev-development s3 bucket to ~/machine-setup
aws s3 cp s3://qapita-dev-development/machine-setup/ ~/machine-setup/ --recursive

export QAPITA_WORKSPACE=~/qapita-workspace

cat << EOF >> ~/.bashrc
export PATH=~/.local/bin:\$PATH
export QAPITA_WORKSPACE=${QAPITA_WORKSPACE}
EOF

cat << EOF >> ~/.zshrc
export PATH=~/.local/bin:\$PATH
export QAPITA_WORKSPACE=${QAPITA_WORKSPACE}
EOF

source "$HOME/.bashrc"

echo set completion-ignore-case on | sudo tee -a /etc/inputrc
clear -x

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

# Install Google Chrome
if ! command -v google-chrome &>/dev/null; then
    install_package_from_url "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
else
    log "Google Chrome is already installed."
fi

# Install Visual Studio Code
if ! command -v code &>/dev/null; then
    # Get the latest version of Visual Studio Code package name
    latest_vscode_package=$(curl -sSL https://packages.microsoft.com/repos/code/pool/main/c/code/ | grep -o 'href="[a-zA-Z0-9._-]*_amd64.deb"' | cut -d'"' -f2 | sort -rV | head -n1)
    install_package_from_url "https://packages.microsoft.com/repos/code/pool/main/c/code/${latest_vscode_package}"
else
    log "Visual Studio Code is already installed."
fi

# Install Node.js with NVM and required packages
# install_nodejs_with_nvm

# Install .NET if not already installed
if ! command -v dotnet &>/dev/null; then
    install_dotnet
else
    log ".NET is already installed."
fi

# Install MongoDB if not already installed
if dpkg-query -W -f='${Status}' "mongodb-org" 2>/dev/null | grep -q "ok installed"; then
    log "MongoDB is already installed."
else
    install_mongodb
fi

# Install EventStoreDB if not already installed
if ! command -v eventstore &>/dev/null; then
    install_eventstore
else
    log "EventStoreDB is already installed."
fi

# Install Docker if not already installed
if ! command -v docker &>/dev/null; then
    install_docker
else
    log "Docker is already installed."
fi

if ! command -v nginx &>/dev/null; then
    install_nginx
else
    log "Nginx is already installed."
fi

# Install Mongo Compass
if ! command -v mongodb-compass &>/dev/null; then
    install_package_from_url "https://downloads.mongodb.com/compass/mongodb-compass_1.39.0_amd64.deb"
else
    log "Mongo Compass is already installed."
fi

# Install PostgreSQL if not already installed
if ! command -v psql &>/dev/null; then
    install_postgresql
else
    log "PostgreSQL is already installed."
fi

#Installing Seq
# Create a Docker container for Seq
sudo docker container create -p 5341:5341 -p 8081:80 \
    -v "${QAPITA_WORKSPACE}/data/seq:/data" \
    -e ACCEPT_EULA=Y \
    --name qapita-seq-local datalust/seq
# Start the Docker container
sudo docker container start qapita-seq-local
# Configure the Docker container to restart always
sudo docker container update --restart always qapita-seq-local

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

if [ -d /etc/ssl/certs ] && [ -d /etc/ssl/private ]; then
    sudo cp ~/machine-setup/certificates/qapitacorp.local-bundle.crt /etc/ssl/certs
    sudo cp ~/machine-setup/certificates/qapitacorp.local.key /etc/ssl/private
    sudo chmod 600 /etc/ssl/private/qapitacorp.local.key
else
    sudo mkdir -p /etc/ssl/certs /etc/ssl/private
    sudo cp ~/machine-setup/certificates/qapitacorp.local-bundle.crt /etc/ssl/certs
    sudo cp ~/machine-setup/certificates/qapitacorp.local.key /etc/ssl/private
    sudo chmod 600 /etc/ssl/private/qapitacorp.local.key
fi

# restart nginx so that our changes are reflected
sudo systemctl restart nginx

# Check if user wants to create swap memory
read -rp "Do you wish to create SWAP Memory? (y/n): " createswap
if [[ $createswap =~ ^[Yy]$ ]]; then
    create_swap_memory
else
    echo "Swap Memory Creation Skipped"
fi

#Cloning Server & client
export QAPITA_WORKSPACE=~/qapita-workspace

clear -x

echo '

                       ___      _    ____ ___ _____  _    
                      / _ \    / \  |  _ \_ _|_   _|/ \   
                     | | | |  / _ \ | |_) | |  | | / _ \  
                     | |_| | / ___ \|  __/| |  | |/ ___ \ 
                      \__\_\/_/   \_\_|  |___| |_/_/   \_\
                                                          
                                                          
'
log ">> 🎉 Machine-Setup 💻 Completed <<"
