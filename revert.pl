#!/usr/bin/perl

# Adapter script for Revert.pm module
# exports Revert.pm functionality for command line use.

use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use Revert;
use Changeset;

if (scalar(@ARGV) < 1 || scalar(@ARGV) > 2)
{
    print <<EOF;
usage: $0 <changeset_to_undo> [ <current_changeset> | <comment>]

where 
  changeset_to_undo : is the id of the changeset you want to revert,
     or the minus sign (-) if you want to read a .osc file from stdin
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
my $nontrivial_comment;

if ($undo_cs eq "-")
{
    $undo_cs = "";
    $undo_cs .= $_ while(<STDIN>);
}

# what have we got, changeset or comment?
if ($current_cs_or_comment =~ /^\d+$/)
{
    $current_cs = $current_cs_or_comment;
}
else
{
    my $comment = $current_cs_or_comment;
    $nontrivial_comment = $comment;
    $comment = "reverting changeset $undo_cs" unless defined($comment);
    $current_cs = Changeset::create($comment);
    $do_close = 1;
}

if (defined($current_cs))
{
    if (Revert::revert($undo_cs, $current_cs, $nontrivial_comment)) 
    {
        if ($do_close)
        {
            Changeset::close($current_cs);
        }
    }
}

