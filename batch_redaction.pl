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
    BatchRedaction::apply($ARGV[1], $ARGV[2], 0);
}
elsif (($ARGV[0] eq "apply-skip") && (scalar(@ARGV) == 3))
{
    BatchRedaction::apply($ARGV[1], $ARGV[2], 1);
}
elsif (($ARGV[0] eq "unapply") && (scalar(@ARGV) == 2))
{
    BatchRedaction::apply($ARGV[1], 0, 0);
}
else
{
    print <<EOF;
Usage: 
  $0 view <filename>                view in xml format osm elements listed in the file
  $0 view.json <filename>           view in json format osm elements listed in the file
  $0 apply <filename> <rid>         redact elements listed in the file, stop immediately on error
  $0 apply-skip <filename> <rid>    redact elements listed in the file, skip an element on error
  $0 unapply <filename>             unredact elements listed in the file

where
  filename : name of file listing element versions; each line is <otype>/<oid>/<oversion>
  rid : redaction id
EOF
    exit;
}
