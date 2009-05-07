#!/usr/bin/perl

# Adapter script for Undo.pm module
# exports Undo.pm functionality for command line use.

use strict;
use warnings;
use Undo;

if (scalar(@ARGV) != 4 || $ARGV[0] !~ /^(node|way|relation)$/)
{
    print <<EOF;
usage: $0 <node|way|relation> <id> <username|changeset> <changeset>

where 
  id : OSM id of the object to revert
  username, changeset : username (alphanumeric) or changeset (numeric) 
     of the change to revert
  changeset : id of changeset to use for revert action
EOF
    exit;
}

my ($what, $id, $undo_what, $changeset) = @ARGV;

my $undo_user;
my $undo_changeset;

if ($undo_what =~ /^\d+$/) { $undo_changeset=$undo_what; } else { $undo_user = $undo_what; }

Undo::undo($what, $id, $undo_user, $undo_changeset, $changeset);

