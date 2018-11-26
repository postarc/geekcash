#!/bin/bash
# makerun.sh
# Make sure geekcashd is always running.
# Add the following to the crontab (i.e. crontab -e)
# */1 * * * * ~/masternode/geekcash/makerun.sh

process=geekcashd01
makerun="geekcashd01"

if ps ax | grep -v grep | grep $process > /dev/null
then
  exit
else
  $makerun &
fi
