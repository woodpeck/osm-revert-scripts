#!/bin/sh

# script to download all changesets of one user since
# a given date (to get ALL, set date to before their signup)
# API currently limited to listing max. 100 changesets, 
# therefore loop required

UID=0
SINCE=2011-09-04T01:53:26

# no user servicable parts below. run this in empty directory 
# and you'll end up with tons of files called c1234.osc (one
# for each changeset)

T=`date -u +%Y-%m-%dT%H:%M:%S`
export T

while true
do

wget -Olist "https://api.openstreetmap.org/api/0.6/changesets?user=$UID&time=$SINCE,$T" 
T=`grep "<changeset" list | tail -1 | cut -d\" -f4`

if grep -q "<changeset" list
then
cat list | grep "<changeset" | cut -d\" -f2 | while read id
do
    rm -f list
    [ -f c$id.osc ] && exit
    wget -Oc$id.osc https://api.openstreetmap.org/api/0.6/changeset/$id/download
done
else
    rm -f list
    exit
fi

done
