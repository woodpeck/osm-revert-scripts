#!/usr/bin/perl

# Adapter script for Revert.pm module
# exports Revert.pm functionality for command line use.

use strict;
use warnings;
use Revert;
use Changeset;

my $revert_creation = 1;

if (scalar(@ARGV) < 1 || scalar(@ARGV) > 2)
{
    print <<EOF;
usage: $0 <changeset_to_undo> [ <current_changeset> | <comment>]

where 
  changeset_to_undo : is the id of the changeset you want to revert
  current_changeset : is the id of a currently open changeset under
     which this action will run.
     If this is given, the changeset will not be closed in order
     to allow you to run multiple operations on the same changeset.
     If unset, a new changeset will be created and closed afterwards.
  comment : the comment to use when closing the changeset (must not
     be numeric lest it would be interpreted as a changeset id).
EOF
    exit;
}

my ($undo_cs, $current_cs_or_comment) = @ARGV;
my $do_close = 0;

my $current_cs;
my $comment; 

# what have we got, changeset or comment?
if ($current_cs_or_comment =~ /^\d+$/)
{
    $current_cs = $current_cs_or_comment;
}
else
{
    $comment = $current_cs_or_comment;
    $comment = "reverting changeset $undo_cs" if ($comment eq "");
    $current_cs = Changeset::create($comment);
    $do_close = 1;
}

if (defined($current_cs))
{
    if (Revert::revert($undo_cs, $current_cs, $revert_creation)) 
    {
        if ($do_close)
        {
            $comment = "reverted changeset $undo_cs" if ($comment eq "");
            Changeset::close($current_cs, $comment);
        }
    }
}

