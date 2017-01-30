#!/usr/bin/perl

# quickdelnode.pl
# ---------------
#
# Deletes a number of nodes quickly, if the majority of them are still
# at v1. Cannot delete Nodes that are part of a way.
#
# Part of the "osmtools" suite of programs
# Originally written by Frederik Ramm <frederik@remote.org>; public domain

use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use Changeset;
use OsmApi;

if (scalar(@ARGV) != 1)
{
    print <<EOF;
usage: $0 {<changeset>|<comment>}

where 
  comment is the comment for the changeset to be created;
  if a changeset ID is given, re-use that changeset.

  node ids are read from stdin.
EOF
    exit;
}

my ($comment) = @ARGV;

my $nodes=[];
while(<STDIN>)
{
    chomp;
    push(@$nodes,$_);
}

my $current_cs;

if ($comment =~ /^[0-9]+$/)
{
    $current_cs = $comment,
}
else
{
    $current_cs = Changeset::create($comment);
}

if (defined($current_cs))
{
    my $nodehash = {};
    foreach my $n(@$nodes) { $nodehash->{$n} = 1 };

    foreach my $n(@$nodes)
    {
        my $resp = OsmApi::delete("node/$n", "<osm version='0.6'>\n<node id='$n' lat='0' lon='0' version='1' changeset='$current_cs' /></osm>");
        if ($resp->is_success)
        {
            printf(STDERR "deleted node $n\n");
            next;
        }
        my $c = $resp->content;
        if ($c =~ /already been deleted/)
        {
            printf(STDERR "already gone node $n\n");
            next;
        }
        if ($c =~ /Version mismatch: Provided 1, server had: (\d+)/)
        {
            my $v=$1;
            $resp = OsmApi::delete("node/$n", "<osm version='0.6'>\n<node id='$n' lat='0' lon='0' version='$v' changeset='$current_cs' /></osm>");
            if ($resp->is_success)
            {
                printf(STDERR "deleted node $n ($v)\n");
                next;
            }
            printf(STDERR "node $n ($v) cannot be deleted: %s\n", $resp->content);
        }
        else
        {
            printf(STDERR "node $n cannot be deleted: %s\n", $resp->content);
        }
    }
    
    Changeset::close($current_cs) unless ($current_cs eq $comment);
}

