#!/usr/bin/perl

# Adapter script for Undelete.pm module
# exports Undelete.pm functionality for command line use.

use strict;
use warnings;
use Undelete;

if (scalar(@ARGV) != 3 || $ARGV[0] !~ /^(node|way|relation)$/)
{
    print <<EOF;
usage: $0 <node|way|relation> <id> <changeset>

where 
  id : OSM id of the object to undelete
  changeset : id of changeset to use for undelete action
EOF
    exit;
}

my ($what, $id, $changeset) = @ARGV;

Undelete::undelete($what, $id, $changeset);

