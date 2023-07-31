#!/usr/bin/perl

use strict;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long;
use Trace;

if ($ARGV[0] eq "create")
{
    my $description = "uploaded with osmtools/$0";
    my $tags;
    my $visibility = "private";
    my $correct_options = GetOptions(
        "description=s" => \$description,
        "tags=s" => \$tags,
        "visibility=s" => \$visibility
    );
    if ($correct_options && (scalar(@ARGV) == 2))
    {
        my $id = Trace::create($ARGV[1], $description, $tags, $visibility);
        print "created a trace with id $id" if defined($id);
        exit;
    }
}

print <<EOF;
Usage: 
  $0 create <filename> <options>   upload new gpx trace

options:
  --description <text>
  --tags <text>
  --visibility <one of: private, public, trackable, identifiable>
EOF
exit;
