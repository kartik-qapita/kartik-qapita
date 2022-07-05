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
mkdir -p ~/machine-setup/{certificates,eventstore,qmap-setup,mongodb} ~/local/.bin

# We need AWS CLI for copying files from our AWS S3 bucket
# Install AWS CLI
sudo apt-get install -y groff less
cd ~/machine-setup
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

clear -x

#Configuring AWS_CREDENTIALS

aws configure sso

#echo "Enter You AWS Profile Name"
#read awsprofileconfigure
#echo "Enter YOUR ACCESS & SECRET KEY"
#aws configure --profile $awsprofileconfigure
# Make sure your AWS_PROFILE environment variable is setup
#sleep 3
# and your AWS credentials are configured in ~/.aws folder
#export AWS_PROFILE=$awsprofileconfigure
#export AWS_REGION=ap-south-1
echo "AWS Profile Configured"
# Configure your AWS environment (you should get the credentials if you don't already have one)
# the following YouTube video will help you with instructions for configuring the AWS environment
# https://www.youtube.com/watch?v=FOK5BPy30HQ


# copy files from qapita-development s3 bucket to ~/machine-setup
aws s3 cp s3://qapita-dev-development/certificates ~/machine-setup/certificates --recursive
aws s3 cp s3://qapita-dev-development/EventStore/v21.10.5/EventStore-Commercial-Linux-v21.10.5.ubuntu-20.04.deb ~/machine-setup/eventstore --recursive
aws s3 cp s3://qapita-dev-development/EventStore/eventstore.conf ~/machine-setup/eventstore --recursive
aws s3 cp s3://qapita-dev-development/EventStore/eventstore-1.pfx ~/machine-setup/eventstore --recursive
aws s3 cp s3://qapita-dev-development/mongodb ~/machine-setup/mongodb --recursive

export QMAP_WORKSPACE=~/qmap-workspace

cat << EOF >> ~/.bashrc
export PATH=~/.local/bin:\$PATH
export QMAP_WORKSPACE=${QMAP_WORKSPACE}
EOF

cat << EOF >> ~/.zshrc
export PATH=~/.local/bin:\$PATH
export QMAP_WORKSPACE=${QMAP_WORKSPACE}
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

# Installing MongoDB
# https://docs.mongodb.com/manual/tutorial/install-mongodb-on-ubuntu/
wget -qO - https://www.mongodb.org/static/pgp/server-4.4.asc | sudo apt-key add -

# Note: this is specific to Ubuntu 18.04
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/4.4 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.4.list

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

# check if /mongodb-data/db folder has files in it
# if /mongodb-data/db folder is empty, then something went wrong
sudo dpkg -i ~/machine-setup/eventstore/EventStore-Commercial-Linux-v21.10.5.ubuntu-20.04.deb
sudo -u eventstore -g eventstore cp ~/machine-setup/eventstore/eventstore.conf /etc/eventstore
sudo -u eventstore -g eventstore cp ~/machine-setup/eventstore/eventstore-1.pfx /etc/eventstore

sudo mkdir -p /eventstoredb-data/{db,log}
sudo chown -R eventstore:eventstore /eventstoredb-data

sudo systemctl enable eventstore
sudo systemctl start eventstore
# to check if eventstore is working fine
sudo systemctl status eventstore

# the folder /eventstoredb-data/db should have the eventstore data
#Installing docker
sudo apt-get remove docker docker-engine docker.io containerd runc
sudo apt-get update

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-key fingerprint 0EBFCD88
sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# add current user to the docker group, this will allow you to run docker command without sudo
# You will have to restart the computer for this to be effective
sudo usermod -aG docker ${USER}


# Install .NET
wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update \
  sudo apt-get install -y apt-transport-https && \
  sudo apt-get update && \
  sudo apt-get install -y dotnet-sdk-6.0

# You should now be able to run the following command
dotnet --version
# if the above command fails, it means dotnet core is not installed

#Intall nvm
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.0/install.sh | bash

export NVM_DIR="$HOME/.nvm"

[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

nvm --version

# Install node version
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.36.0/install.sh | bash

export NODE_LTS=v14.16.1
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

mkdir -p ${QMAP_WORKSPACE}/data/seq

sudo docker container create -p 5341:5341 -p 8081:80 \
    -v ${QMAP_WORKSPACE}/data/seq:/data \
    -e ACCEPT_EULA=Y \
    --name q-seq-node datalust/seq

sudo docker container start q-seq-node
sudo docker container update --restart always q-seq-node

# Installing NGINX 1.20.2
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


#Cloning Server & client
export QMAP_WORKSPACE=~/qmap-workspace
# Clone the server repository and restore nuget packages
git clone git@github.com:qapita/captable-writemodel.git ${QMAP_WORKSPACE}/server

clear -x

#Nuget key from github
cd ${QMAP_WORKSPACE}/server/
#Replace Default value with Generated Nuget Key in nuget.config
echo "ENTER YOUR NUGET KEY"
read nugetkey
sed -i 's/%NUGET_SECRET_ACCESS_KEY%/\'$nugetkey'/' nuget.config

# restore nuget packages
pushd ${QMAP_WORKSPACE}/server/src/WebAPI && dotnet restore && popd
pushd ${QMAP_WORKSPACE}/server/src/IDP && dotnet restore && popd
pushd ${QMAP_WORKSPACE}/server/src/WebConsole && dotnet restore && popd
pushd ${QMAP_WORKSPACE}/server/src/Qapita.QMap.UserTaskManagement && dotnet restore && popd

# make sure your eventstore and mongodb are running before the following commands are executed
cd ${QMAP_WORKSPACE}/server/src/IDP
cp appsettings.Development.Template.json appsettings.Development.json
dotnet run /seed

cd ${QMAP_WORKSPACE}/server/src/WebAPI
cp appsettings.Development.template.json appsettings.Development.json

#dotnet run /setup

cd ${QMAP_WORKSPACE}/server/src/Qapita.QMap.UserTaskManagement
cp appsettings.Development.Template.json appsettings.Development.json

# the following command will start the backend services
#cd ${QMAP_WORKSPACE}/server/
#./start-services.sh


# you can verify that the CapTable service is running fine by executing the following command:
#curl https://captable.qapitacorp.local/api/v1/static/data

# Clone the qmap client repository
git clone git@github.com:qapita/captable-web.git ${QMAP_WORKSPACE}/client

# required to build node-sass
sudo apt install -y build-essential

# bootstrap the lerna packages
pushd ${QMAP_WORKSPACE}/client && lerna bootstrap && popd
pushd ${QMAP_WORKSPACE}/client/packages/web
npm rebuild node-sass
# to launch the client
#npm start
# Installing yarn in global
echo "Installing yarn globally"
npm install --global yarn
echo "Your yarn version is"
yarn --version
# Changing directory to Qmap-Client
echo "Changing Directory to client"
cd ${QMAP_WORKSPACE}/client
# Cleaning previous dependancies from node_modules
echo "Removing node_modules..."
yes | lerna clean
# Removing node_modules inside client
echo "Removing node_modules inside client"
rm -rf node_modules
# Unlink all symlinks
echo "Unlinking all symlinks"
yarn unlink-all
# Link all symlinks
echo "Linking all symlinks"
yarn link-all
# Changing to web package
echo "Changing to web package"
cd packages/web
# Startin web server
echo "Starting web server"
#yarn start
# you will need to wait for a few minutes for the webpack build to complete
# open https://qmap.qapitacorp.local in chrome
#curl https://qmap.qapitacorp.local
clear -x

echo "Installed - AWS-cli , Git, Eventstore, Mongodb, Docker, Nginx, Dotnet, Node"
echo ">> 🎉 Machine-Setup 💻 Completed <<"
