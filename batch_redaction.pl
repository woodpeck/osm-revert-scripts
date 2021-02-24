#!/usr/bin/perl

use strict;
use FindBin;
use lib $FindBin::Bin;
use BatchRedaction;

if (($ARGV[0] eq "view") && (scalar(@ARGV) == 2))
{
    BatchRedaction::view($ARGV[1]);
}
elsif (($ARGV[0] eq "view.json") && (scalar(@ARGV) == 2))
{
    BatchRedaction::view($ARGV[1], ".json");
}
elsif (($ARGV[0] eq "apply") && (scalar(@ARGV) == 3))
{
    BatchRedaction::apply($ARGV[1], $ARGV[2]);
}
else
{
    print <<EOF;
Usage: 
  $0 view <filename>          to view in xml format osm elements listed in file; each line is <otype>/<oid>/<oversion>
  $0 view.json <filename>     to view in json format osm elements listed in file; each line is <otype>/<oid>/<oversion>
  $0 apply <filename> <id>    to do redactions from file; each line is <otype>/<oid>/<oversion>
EOF
    exit;
}
