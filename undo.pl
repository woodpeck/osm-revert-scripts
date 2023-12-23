#!/usr/bin/perl

# Adapter script for Undo.pm module
# exports Undo.pm functionality for command line use.

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Undo;
use Getopt::Long;

my $force = 0;

usage() unless GetOptions("force" => \$force);
usage() unless (scalar(@ARGV) == 4 && $ARGV[0] =~ /^(node|way|relation)$/);

sub usage
{
    print <<EOF;
usage: $0 [--force] <node|way|relation> <id> <username|changeset> <changeset>

where 
  id : OSM id of the object to revert
  username, changeset : username (alphanumeric) or changeset (numeric) 
     of the change to revert
  changeset : id of changeset to use for revert action
  when --force is given, overrides subsequent changes
EOF
    exit;
}

my ($what, $id, $undo_what, $changeset) = @ARGV;

my $undo_user;
my $undo_changeset;

if ($undo_what =~ /^[0-9]+(,[0-9]+)*$/) 
{ 
    foreach (split(/,/, $undo_what))
    {
        $undo_changeset->{$_} = 1;
    } 
} 
else 
{ 
    foreach (split(/,/, $undo_what))
    {
        $undo_user->{$_} = 1;
    } 
}

exit 1 if (!defined(Undo::undo($what, $id, $undo_user, $undo_changeset, undef, $changeset, $force)));
exit 0

