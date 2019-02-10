#!/bin/bash
# checkdaemon.sh
# Make sure the daemon is not stuck.
# Add the following to the crontab (i.e. crontab -e)
# */30 * * * * ~/masternode/geekcash/checkdaemon.sh

previousBlock=$(cat ~/masternode/geekcash/blockcount)
currentBlock=$(geekcash-cli getblockcount)

geekcash-cli getblockcount > ~/masternode/geekcash/blockcount

if [ "$previousBlock" == "$currentBlock" ]; then
  pID=$(ps -u $USER | grep geekcashd | awk '{print $1}')
  kill -9 ${pID}
  geekcashd
fi
