#!/usr/bin/perl

# Adapter script for Delete.pm module
# exports Delete.pm functionality for command line use.

use strict;
use warnings;
use Delete;

if (scalar(@ARGV) != 3 || $ARGV[0] !~ /^(node|way|relation)$/)
{
    print <<EOF;
usage: $0 <node|way|relation> <id> <changeset>

where 
  id : OSM id of the object to delete
  changeset : id of changeset to use for delete action
EOF
    exit;
}

my ($what, $id, $changeset) = @ARGV;

Delete::delete($what, $id, $changeset);

