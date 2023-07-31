#!/usr/bin/perl

use strict;
use FindBin;
use lib $FindBin::Bin;
use Trace;

if (($ARGV[0] eq "create") && (scalar(@ARGV) == 2))
{
    Trace::create($ARGV[1]);
}
else
{
    print <<EOF;
Usage: 
  $0 create <filename>    upload new gpx trace
EOF
    exit;
}
