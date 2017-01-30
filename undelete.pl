#!/usr/bin/perl

# Adapter script for Undelete.pm module
# exports Undelete.pm functionality for command line use.

use strict;
use warnings;
use FindBin; 
use lib $FindBin::Bin;
use Undelete;

if (scalar(@ARGV) < 3 || $ARGV[0] !~ /^(node|way|relation)$/)
{
    print <<EOF;
usage: $0 <node|way|relation> <id> <changeset> [<tag>]

where 
  id : OSM id of the object to undelete
  changeset : id of changeset to use for undelete action
  tag: (optional) only undelete things with this tag
EOF
    exit;
}

my ($what, $id, $changeset, $key) = @ARGV;

Undelete::undelete($what, $id, $changeset, $key);

