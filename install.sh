#!/bin/bash
# install.sh
# Installs masternode on Ubuntu 16.04 x64 & Ubuntu 18.04
# ATTENTION: The anti-ddos part will disable http, https and dns ports.
BINTAR='geekcash-1.2.0-x86_64-linux-gnu.tar.gz'
BINADDR='https://github.com/GeekCash/geekcash/releases/download/v1.2.0.1/geekcash-1.2.0-x86_64-linux-gnu.tar.gz'
BPATH='geekcash-1.2.0/bin'
RPCPORT=6888
PORT=6889
COIN_PORT=6889
TRYCOUNT=7
WAITP=10

sudo apt-get install -y curl
sudo apt-get install -y lsof

while [ -n "$(sudo lsof -i -s TCP:LISTEN -P -n | grep $RPCPORT)" ]
do
(( RPCPORT--))
done
echo -e "\e[32mFree RPCPORT address:$RPCPORT\e[0m"
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
rm -rf ~/.geekcash/backups
rm -rf ~/..geekcash/sentinel
rm  ~/.geekcash/*
#mkdir ~/.geekcash/
#touch ~/.geekcash/geekcash.conf

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
${external_ip_line}
masternodeprivkey=${_nodePrivateKey}
port=$PORT
" > geekcash.conf

# Get a new privatekey by going to console >> debug and typing masternode genkey
printf "Enter Masternode PrivateKey: "
read _nodePrivateKey
if [[ -z "$_nodePrivateKey" ]]; then
  geekcashd -daemon
  sleep 5
  if [ -z "$(ps axo cmd:100 | grep geekcashd)" ]; then
   echo -e "${GREEN}$COIN_NAME server couldn not start."
   exit 1
  fi
_nodePrivateKey=$(geekcash-cli masternode genkey)
ERROR=$?
while [ "$ERROR" -gt "0" ] && [ "$TRYCOUNT" -gt "0" ]
do
  sleep $WAITP
 _nodePrivateKey=$(geekcash-cli masternode genkey)
  ERROR=$?
    if [ "$ERROR" -gt "0" ];  then
      echo "Wallet not fully loaded. Let us wait and try again to generate the Private Key"
    fi
  TRYCOUNT=$[TRYCOUNT-1]
  done
geekcash-cli stop
sleep 5
fi
if [[ -z "$_nodePrivateKey" ]]; then 
echo "Masternode key could not be generated. Edit the config file manually."
fi
echo -e "\e[32mCreate the initial geekcash.conf file\e[0m"
# Write masternode privat key to geekcash.conf file
echo -e "
masternode=1
masternodeprivkey=${_nodePrivateKey}
" >> geekcash.conf

cd

# Download geekcash and put executable to /usr/local/bin
#wget -qO- --no-check-certificate --content-disposition 
if [ -f "/usr/local/bin/geekcashd" ]; then
    echo -e "\e[32mBin files exist, skipping copy.\e[0m"
else
	echo -e "\e[32mGeekCash downloading...\e[0m"
	echo "get and unzip..."
	mkdir temp
	cd temp
	wget $BINADDR 
	tar -xzvf $BINTAR
	#curl -LJO $BINADDR
	#tar -xzvf $BINTAR
	echo -e "\e[32mPut executable to /usr/local/bin\e[0m"
	sudo bash -c "cp ./$BPATH/geekcashd /usr/local/bin/"
	sudo bash -c "cp ./$BPATH/geekcash-cli /usr/local/bin/"
	sudo chmod +x /usr/local/bin/geekcash*
	cd 
	rm -rf temp
fi 

# Create a directory for masternode's cronjobs and the anti-ddos script
#rm -rf masternode/geekcash
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
if ! crontab -l | grep "@reboot /usr/local/bin/geekcashd"; then
  (crontab -l ; echo "@reboot /usr/local/bin/geekcashd") | crontab -
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
if ! crontab -l | grep "~/.geekcash/sentinel"; then
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
sudo ufw allow $PORT/tcp
sudo ufw allow $RPCPORT/tcp
sudo ufw allow ssh
sudo ufw logging on
sudo ufw default allow outgoing
sudo ufw --force enable

# Start GeekCash Deamon
geekcashd
cd
rm -rf geekcash
# Reboot the server
#reboot
