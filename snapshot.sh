#!/bin/bash
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#
#ARK Blockchain Snapshot Script
#
#by tharude a.k.a The Forging Penguin
#
#11/03/2017 ARK Team
#
#Ported to Blockpool by billotronic
#
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#
#~~~~~~~~~~~~~~~~~~~~ INSTRUCTIONS ~~~~~~~~~~~~~~~~~~~#
#
#Edit crontab by typing "sudo nano /etc/crontab"
#
#Put at the end of file the following line to make
#
#the script creating snapshots every 15 minutes:
#
#*/15 * * * * user /path/to/snapshot.sh
#
#Replace the "user" with your username
#
#and path at the end with your real script path.
#
#Save the file with Ctrl+x and Y when you're done

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

#VARIABLES

DB_NAME="bpl_mainnet"
HEIGHT="$(psql -d $DB_NAME -t -c 'select height from blocks order by height desc limit 1;' | xargs)"
NODE_DIR="$HOME/BPL-node"
EXPLORER_DIR="$HOME/BPL-explorer"
PUBLIC_DIR="$HOME/BPL-explorer/public"
SNAPDIR="snapshots"
LOG="$HOME/snapshot.log"
DATE=`date +%Y-%m-%d\ %H:%M:%S`

#~ SEED NODES ~#

seed0=("54.219.247.231:9030" "seed01")
seed1=("54.241.220.135:9030" "seed02")
seed2=("54.241.232.217:9030" "seed03")
seed3=("54.241.43.96:9030" "seed04")
seed4=("54.241.69.119:9030" "seed05")

#~ API CALL ~#

apicall="/api/loader/status/sync"

#~ ARRAYS ~#

declare -a nodes=(seed0[@] seed1[@] seed2[@] seed3[@] seed4[@])
declare -a height=()

#Get array length

arraylength=${#nodes[@]}

#Spawning curl netheight processes loop

for n in {1..$arraylength..$arraylength}; do
    for (( i=1; i<${arraylength}+1; i++ )); do
        saddr=${!nodes[i-1]:0:1}
        echo $i $(curl -m 3 -s $saddr$apicall | cut -f 5 -d ":" | sed 's/,.*//' | sed 's/}$//') >> $HOME/tout.txt &
    done
    wait
done
#Array read

while read ind line; do
height[$ind]=$line # assign array values
done < $HOME/tout.txt
rm $HOME/tout.txt

#Finding the highest block

IFS=$'\n'
highest=($(sort -nr <<<"${height[*]}"))
unset IFS

#~~~~~ SNAPSHOT ~~~~~

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" >> $LOG
echo "$DATE -- Snapshot process started" >> $LOG

[ -d $PUBLIC_DIR/$SNAPDIR ] && echo "$DATE -- Snapshot directory exists" >> $LOG || mkdir $PUBLIC_DIR/$SNAPDIR

node=`pgrep -a "node" | grep BPL-node | awk '{print $1}'`

if [ "$node" == "" ] ; then
    node=0
    echo "$DATE -- No Blockpool Node process is running! Starting..." >> $LOG
    forever --plain start app.js --genesis genesisBlock.mainnet.json --config config.mainnet.json >> $LOG 2>&1
    explorer=`pgrep -a "node" | grep BPL-explorer | awk '{print $1}'`
    if [ "$explorer" == "" ] ; then
        explorer=0
        echo "$DATE -- No Blockpool Explorer process is running! Starting..." >> $LOG
        cd $EXPLORER_DIR
        NODE_ENV=production forever --plain start app.js >> $LOG 2>&1
        cd $HOME
    fi
else
    forever_process=`forever --plain list | grep $node | sed -nr 's/.*\[(.*)\].*/\1/p'`
    if [ "$HEIGHT" == "$highest" ]; then
        echo "$DATE -- Blockpool Node process is running with forever PID: $forever_process" >> $LOG
        echo "$DATE -- Local DB Blockheight: $HEIGHT -- Network Blockheight: $highest" >> $LOG
        cd $NODE_DIR
        echo "$DATE -- Snapshot creation path: $PUBLIC_DIR/$DB_NAME"_"$HEIGHT" >> $LOG
        echo "$DATE -- Stopping the node process..." >> $LOG
        forever --plain stop $forever_process >> $LOG 2>&1
        sleep 1
        echo "$DATE -- Dump of $DB_NAME at height $HEIGHT started" >> $LOG
        pg_dump -O bpl_mainnet -Fc -Z6 > $PUBLIC_DIR/$SNAPDIR/$DB_NAME"_"$HEIGHT
        echo "$DATE -- Dump of $DB_NAME at height $HEIGHT finished" >> $LOG
        sleep 1
        echo "$DATE -- Relinking CURRENT to $DB_NAME"_"$HEIGHT" >> $LOG
        rm $PUBLIC_DIR/current
        ln -s $PUBLIC_DIR/$SNAPDIR/$DB_NAME"_"$HEIGHT $PUBLIC_DIR/current
        echo "$DATE -- Starting Blockpool Node process..." >> $LOG
        forever --plain start app.js --genesis genesisBlock.mainnet.json --config config.mainnet.json >> $LOG 2>&1
        echo "$DATE -- Cleaning up old snapshots..." >> $LOG
        find $PUBLIC_DIR/$SNAPDIR -maxdepth 1 -mmin +60 -type f -exec ls -lt {} + | grep -v ":00" | awk '{ print $9}' | xargs -r rm
        find $PUBLIC_DIR/$SNAPDIR -maxdepth 1 -ctime +3 -type f -exec ls -lt {} + | awk '{ print $9}' | xargs -r rm
        cd $HOME
        echo "$DATE -- Snapshot process finished" >> $LOG
    else
        echo "$DATE -- Node is out of sync, restarting!"
        cd $NODE_DIR
        forever --plain restart $forever_process >> $LOG 2>&1
        cd $HOME
    fi
fi
