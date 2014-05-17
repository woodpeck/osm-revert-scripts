#!/bin/sh

# script to download all changesets of one user since
# a given date (to get ALL, set date to before their signup)
# API currently limited to listing max. 100 changesets, 
# therefore loop required

USER=someuser
SINCE=2013-11-01T00:00:00

# no user servicable parts below. run this in empty directory 
# and you'll end up with tons of files called c1234.osc (one
# for each changeset)

T=`date -u +%Y-%m-%dT%H:%M:%S`
export T

while /bin/true
do

wget -Olist "http://api.openstreetmap.org/api/0.6/changesets?display_name=$USER&time=$SINCE,$T" 
T=`grep "<changeset" list|tail -1|cut -d\" -f8`

if grep -q "<changeset" list 
then
cat list | grep "<changeset" | cut -d\" -f2 | while read id
do
    rm -f list
    [ -f c$id.osc ] && exit
    wget -Oc$id.osc http://api.openstreetmap.org/api/0.6/changeset/$id/download
done
else
    rm -f list
    exit
fi

done
