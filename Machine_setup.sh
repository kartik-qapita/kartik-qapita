#!/usr/bin/env bash
echo "QAPITA : 💻 MACHINE-SETUP"

# some basic software
sudo apt install -y \
    openssh-server tmux git \
    build-essential \
    ca-certificates \
    apt-transport-https \
    curl wget \
    gnupg-agent \
    software-properties-common

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
read installcode

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
read installteams

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

# We need AWS CLI for copying files from our AWS S3 bucket
# Install AWS CLI
sudo apt-get install -y groff less
cd ~/machine-setup
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

clear -x

#Configuring AWS_CREDENTIALS

echo "Enter You AWS Profile Name : (eg. qapita-yourname)"
read awsprofileconfigure

aws configure sso
#echo "Enter YOUR ACCESS & SECRET KEY"
#aws configure --profile $awsprofileconfigure
# Make sure your AWS_PROFILE environment variable is setup
#sleep 3
# and your AWS credentials are configured in ~/.aws folder
export AWS_PROFILE=$awsprofileconfigure
export AWS_REGION=ap-south-1
#echo "AWS Profile Configured"
#to confirm that aws is configured
aws s3 ls

printf 'Are the AWS S3 Buckets Listed above (y/n)? '
read awss3

if [ "$awss3" != "${awss3#[Yy]}" ] ;then
    echo "AWS Profile is configured"
else
    echo "AWS Profile Configuration not completed, please check the AWS SSO Configuration Guide"
    exit
fi

# Configure your AWS environment (you should get the credentials if you don't already have one)
# the following YouTube video will help you with instructions for configuring the AWS environment
# https://www.youtube.com/watch?v=FOK5BPy30HQ

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

# mkdir -p ~/.ssh

cat << EOF >> ~/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCM71oLD28cZBv7bF1hy0VdzktED1BpPqWoRNVxm2eu+GysBwIRSrCjH/iVNvnkQTYex89VounL/XFMazCN2Wy3RxgpScKoIY+hic8o3iGt+3ms9kl8SwQNd17TovLoVPa42jWsCAM+EMGliiWxab5IkxSpQk6yGhRY0D/svaqyuRk0O+m0ry8uMHaQRX8q0gHEpm3nzNxlX7adFMUnz9fPigWLAP0FK+J9rAeWNoetbpVIQVPN7sMeuqPY/93qnJhQ9mPSOpxJRMVOQTMk2BPXuZu9MUc6O1XFf76rKafRCW99AekQDQHcwwdd3plE8Gr+NwcsnSFN0n7BYl5QjQnV
EOF

chmod 600 ~/.ssh/authorized_keys

echo set completion-ignore-case on | sudo tee -a /etc/inputrc

clear -x

# Configuring Git
echo "Enter Your Git-Hub Username"
read githubusername
git config --global user.name $githubusername

sleep 3
echo "Enter Your Qapita Email Id"
read qapitaemail
git config --global user.email $qapitaemail



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

export pkgeventstore=eventstore
dpkg -s $pkgeventstore &> /dev/null

if [ $? -ne 0 ] ;then
echo "Installing EventstoreDB"

sudo dpkg -i ~/machine-setup/eventstoredb/EventStore-Commercial-Linux-v21.10.5.ubuntu-20.04.deb
sudo -u eventstore -g eventstore cp ~/machine-setup/eventstoredb/eventstore.conf /etc/eventstore
sudo -u eventstore -g eventstore cp ~/machine-setup/eventstoredb/eventstore.pfx /etc/eventstore

sudo mkdir -p /eventstoredb-data/{db,log}
sudo chown -R eventstore:eventstore /eventstoredb-data

sudo systemctl enable eventstore
sudo systemctl start eventstore
# to check if eventstore is working fine
sudo systemctl status eventstore

else
    echo    "Skipping installation, EventstoreDB was already installed"
fi

# the folder /eventstoredb-data/db should have the eventstore data
#Installing docker

export pkgdocker=docker
dpkg -s $pkgdocker &> /dev/null

if [ $? -ne 0 ] ;then
echo "Installing Docker"

sudo apt-get remove docker docker-engine docker.io containerd runc
sudo apt-get update
sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo chmod a+r /etc/apt/keyrings/docker.gpg
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin

# sudo apt-get update
# sudo apt-get install -y docker-ce docker-ce-cli containerd.io
# sudo curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
# sudo chmod +x /usr/local/bin/docker-compose

# add current user to the docker group, this will allow you to run docker command without sudo
# You will have to restart the computer for this to be effective
sudo usermod -aG docker ${USER}

else
    echo    "Skipping installation, Docker was already installed"
fi


# Installing MongoDB

# Installing mongodb based on os version
export OSVERSION=$(lsb_release -rs)

if [ $OSVERSION = "20.04" ]  ;then
    echo "Installing MongoDB"
    # wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | sudo apt-key add -

    # # Note: this is specific to Ubuntu 20.04
    # echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list

    # sudo apt-get update
    # sudo apt-get install -y mongodb-org

    wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | sudo apt-key add -
    sudo apt-get install gnupg
    wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | sudo apt-key add -
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list
    sudo apt-get update
    sudo apt-get install -y mongodb-org

    # edit /etc/mongod.conf
    sudo mkdir -p /mongodb-data/{db,log}
    sudo chown -R mongodb:mongodb /mongodb-data
    # replace the mongodb configuration file in /etc folder
    sudo cp ~/machine-setup/mongodb/mongod.conf /etc
    # make sure mongodb starts when the machine boots
    sudo systemctl enable mongod
    # restart now for the config changes to be effective
    sudo systemctl restart mongod
    # check the status of the mongodb service (confirm that it is running)
    sudo systemctl status mongod

elif [ $OSVERSION = "22.04" ] ; then
    echo "Installing MongoDB in Docker"
    # edit /etc/mongod.conf
    sudo mkdir -p /mongodb-data/{db,log}
    sudo chown -R mongodb:mongodb /mongodb-data
    # replace the mongodb configuration file in /etc folder
    sudo cp ~/machine-setup/mongodb/mongod.conf /etc
    # Run docker image
    docker run --name mongodb -p 27017:27017 -d -v /mongodb-data/db:/data/db mongo:6.0.3
else
    echo    "Skipping installation, MongoDB was already installed"
fi


# Install .NET

export pkgdotnet=dotnet
dpkg -s $pkgdotnet &> /dev/null

if [ $? -ne 0 ] ;then
echo "Installing Dotnet 6"

wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y dotnet-sdk-6.0

# You should now be able to run the following command
else
    echo    "Skipping installation, Dotnet was already installed"
    dotnet --version
fi

# if the above command fails, it means dotnet core is not installed

# Install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.2/install.sh | bash

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

# Installing NGINX 1.20.2
export pkgnginx=nginx
dpkg -s $pkgnginx &> /dev/null

if [ $? -ne 0 ] ;then
echo "Installing Nginx"

(cat << EOF
deb https://nginx.org/packages/ubuntu/ $(lsb_release -cs) nginx
deb-src https://nginx.org/packages/ubuntu/ $(lsb_release -cs) nginx
EOF
) | sudo tee /etc/apt/sources.list.d/nginx.list
echo
sudo apt-get update
echo
export key=ABF5BD827BD9BF62
echo
# If key error, copy the key to environment variable "key" and run the below command ABF5BD827BD9BF62
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys $key
sudo apt-get update
sudo apt-get remove -y nginx
sudo apt install -y nginx

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

else
    echo    "Skipping installation, Nginx was already installed"
fi

# Creating SWAP Memory
printf '(Optional) - Do you wish to create SWAP Memory (y/n)? '
read createswap

if [ "$createswap" != "${createswap#[Yy]}" ] ;then

    echo Creating swapfile
    echo "Enter the size of swap needed (eg. 16 for 16GB of swap)"
    read swap
    sudo fallocate -l ${swap}G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab

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
