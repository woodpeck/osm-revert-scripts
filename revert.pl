#!/usr/bin/perl

# Adapter script for Revert.pm module
# exports Revert.pm functionality for command line use.

use strict;
use warnings;
use Revert;
use Changeset;

if (scalar(@ARGV) < 1 || scalar(@ARGV) > 2)
{
    print <<EOF;
usage: $0 <changeset_to_undo> [ <current_changeset> ]

where 
  changeset_to_undo : is the id of the changeset you want to revert
  current_changeset : is the id of a currently open changeset under
     which this action will run.
     If unset, a new changeset will be created.
EOF
    exit;
}

my ($undo_cs, $current_cs) = @ARGV;
my $do_close = 0;

if (!defined($current_cs))
{
    $current_cs = Changeset::create();
    $do_close = 1;
}

if (defined($current_cs))
{
    if (Revert::revert($undo_cs, $current_cs)) 
    {
        if ($do_close)
        {
            Changeset::close($current_cs, "reverted changeset $undo_cs");
        }
    }
}

