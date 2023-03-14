#!/bin/sh

# script to download all changesets of one user since
# a given date (to get ALL, set date to before their signup)
# API currently limited to listing max. 100 changesets, 
# therefore loop required

UID=$1
SINCE=2013-11-01T00:00:00

# no user servicable parts below. run this in empty directory 
# and you'll end up with tons of files called c1234.osc (one
# for each changeset)

T=`date -u +%Y-%m-%dT%H:%M:%S`
export T
EX=0
export EX

while [ $EX = 0 ]
do
    wget -Olist "https://api.openstreetmap.org/api/0.6/changesets?user=$UID&time=$SINCE,$T" 
    T=`grep "<changeset" list | tail -1 | cut -d\" -f4`
    T=`date +"%Y-%m-%dT%H:%M:%SZ" -u -d "$T + 1 second"`

    EX=1
    cat list | grep "<changeset" | cut -d\" -f2 | while read id
    do
        if [ -f c$id.osc ]
        then
            :
        else
            wget -Oc$id.osc https://api.openstreetmap.org/api/0.6/changeset/$id/download
            EX=0
        fi
    done
done

rm -f list
