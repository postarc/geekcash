#!/bin/bash
# install.sh
# Installs masternode on Ubuntu 16.04 x64 & Ubuntu 18.04
# ATTENTION: The anti-ddos part will disable http, https and dns ports.
RPCPORT=6888
PORT=6889
COIN_PORT=6889

while [ -n "$(sudo lsof -i -s TCP:LISTEN -P -n | grep $RPC_PORT)" ]
do
(( RPC_PORT--))
done
echo -e "\e[32mFree RPCPORT address:$RPC_PORT\e[0m"
while [ -n "$(sudo lsof -i -s TCP:LISTEN -P -n | grep $PORT)" ]
do
(( PORT++))
done
echo -e "\e[32mFree MN port address:$PORT\e[0m" 

if [[ $EUID -eq 0 ]] && [ "$USER" != "root" ]; then
   echo -e "${RED}$0 must be run whithout sudo.${NC}"
   exit 1
fi 

while true; do
 if [ -d ~/.geekcash ]; then
   printf "~/.geekcash/ already exists! The installer will delete this folder. Continue anyway?(Y/n):"
   read REPLY
   if [ ${REPLY} == "Y" ]; then
	pID=$(ps -u $USER -ef | grep geekcashd | awk '{print $2}')
	sudo kill ${pID} && sleep 5     
    break
   else
      if [ ${REPLY} == "n" ]; then
        exit
      fi
   fi
 else
   break
 fi
done

cd

# Get a new privatekey by going to console >> debug and typing masternode genkey
printf "Enter Masternode PrivateKey: "
read _nodePrivateKey

# The RPC node will only accept connections from your localhost
_rpcUserName=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12 ; echo '')

# Choose a random and secure password for the RPC
_rpcPassword=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32 ; echo '')

# Get the IP address of your vps which will be hosting the masternode
apt install curl -y
_nodeIpAddress=`curl ifconfig.me/ip`
#_nodeIpAddress=$(curl -s 4.icanhazip.com)
if [[ ${_nodeIpAddress} =~ ^[0-9]+.[0-9]+.[0-9]+.[0-9]+$ ]]; then
  external_ip_line="externalip=${_nodeIpAddress}:$COIN_PORT"
else
  external_ip_line="#externalip=external_IP_goes_here:$COIN_PORT"
fi
# Make a new directory for geekcash daemon
rm -rf ~/.geekcash/
mkdir ~/.geekcash/
touch ~/.geekcash/geekcash.conf

# Change the directory to ~/.geekcash
cd ~/.geekcash/

echo -e "\e[32mCreate the initial geekcash.conf file\e[0m"
# Create the initial geekcash.conf file
echo -e "rpcuser=${_rpcUserName}
rpcpassword=${_rpcPassword}
rpcallowip=127.0.0.1
rpcport=$RPCPORT
listen=1
server=1
daemon=1
logtimestamps=1
maxconnections=64
txindex=1
masternode=1
${external_ip_line}
masternodeprivkey=${_nodePrivateKey}
port=$PORT
" > geekcash.conf
cd

# Download geekcash and put executable to /usr/local/bin

#wget -qO- --no-check-certificate --content-disposition 
echo -e "\e[32mGeekCash downloading...\e[0m"
https://github.com/GeekCash/geekcash/releases/download/v1.0.1.2/geekcash-1.0.1-x86_64-linux-gnu.tar.gz | tar -xzvf geekcash-1.0.1-x86_64-linux-gnu.tar.gz


curl -LJO https://github.com/GeekCash/geekcash/releases/download/v1.0.1.3/geekcash-1.0.1-x86_64-linux-gnu.tar.gz

echo "unzip..."
tar -xzvf ./geekcash-1.0.1-x86_64-linux-gnu.tar.gz
chmod +x ./geekcash-1.0.1/bin/


echo "Put executable to /usr/bin"
cp ./geekcash-1.0.1/bin/geekcashd /usr/bin/
cp ./geekcash-1.0.1/bin/geekcash-cli /usr/bin/


rm -rf ./geekcash-1.0.1
rm -rf ./geekcash-1.0.1-x86_64-linux-gnu.tar.gz


# Create a directory for masternode's cronjobs and the anti-ddos script
rm -r masternode/geekcash
mkdir -p masternode/geekcash

# Download the appropriate scripts
cp geekcash/makerun.sh masternode/geekcash
cp geekcash/checkdaemon.sh masternode/geekcash
cp geekcash/clearlog.sh masternode/geekcash

#Sentinel installing
echo -e "\e[32mSentinel installing...\e[0m"
sudo apt-get update
sudo apt-get install python
sudo apt-get -y install python-virtualenv

cd ~ && cd .geekcash
git clone https://github.com/geekcash/sentinel.git && cd sentinel
virtualenv ./venv
./venv/bin/pip install -r requirements.txt

# Create a cronjob for making sure geekcashd runs after reboot
echo -e "\e[32mCreate a cronjob for making sure geekcashd runs after reboot\e[0m"
if ! crontab -l | grep "@reboot geekcashd"; then
  (crontab -l ; echo "@reboot geekcashd") | crontab -
fi

# Create a cronjob for making sure geekcashd is always running
if ! crontab -l | grep "~/masternode/geekcash/makerun.sh"; then
  (crontab -l ; echo "*/5 * * * * ~/masternode/geekcash/makerun.sh") | crontab -
fi

# Create a cronjob for making sure the daemon is never stuck
if ! crontab -l | grep "~/masternode/geekcash/checkdaemon.sh"; then
  (crontab -l ; echo "*/30 * * * * ~/masternode/geekcash/checkdaemon.sh") | crontab -
fi

# Create a cronjob for clearing the log file
if ! crontab -l | grep "~/masternode/geekcash/clearlog.sh"; then
  (crontab -l ; echo "0 0 */2 * * ~/masternode/geekcash/clearlog.sh") | crontab -
fi

# Create a cronjob for sentinel 
if ! crontab -l | grep "cd /root/.geekcash/sentinel"; then
  (crontab -l ; echo "* * * * * cd ~/.geekcash/sentinel && ./venv/bin/python bin/sentinel.py >/dev/null 2>&1") | crontab -
fi

# Change the directory to ~/masternode/
cd ~/masternode/geekcash

# Give execute permission to the cron scripts
chmod 0700 ./makerun.sh
chmod 0700 ./checkdaemon.sh
chmod 0700 ./clearlog.sh

# Firewall security measures
sudo apt install ufw -y
sudo ufw allow $PORT
sudo ufw allow ssh
sudo ufw logging on
sudo ufw default allow outgoing
sudo ufw --force enable

# Start GeekCash Deamon
geekcashd

# Reboot the server
#reboot
