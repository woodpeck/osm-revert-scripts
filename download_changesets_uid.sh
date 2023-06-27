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

# There are two loops here.  We exit the outer one if we try 
# to obtain some changesets and fail to do so
# ("EX=1" means "exit the outer loop").
# The inner loop is just determined by reading the list.

while [ $EX = 0 ]
do
    wget -Olist.$$ "https://api.openstreetmap.org/api/0.6/changesets?user=$UID&time=$SINCE,$T" 
    T=`grep "<changeset" list.$$ | tail -1 | cut -d\" -f4`

# A previous version attempted to check for "multiple changesets in the same second" by doing
#    T=`date +"%Y-%m-%dT%H:%M:%SZ" -u -d "$T + 1 second"`
# That didn't work but went unnoticed because the outer loop exit logic was always true previously 
# With the required "if" just below, it was always false and looped forever.
# (the last changeset we had just read was always still there).

    if grep -q '<changeset' list.$$
    then
	EX=0
    else
	EX=1
    fi
    
    cat list.$$ | grep '<changeset' | cut -d\" -f2 | while read id
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

rm -f list.$$
