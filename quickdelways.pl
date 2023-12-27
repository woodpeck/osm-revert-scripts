#!/usr/bin/perl

# quickdelways.pl
# ---------------
#
# Deletes a number of ways quickly, if the majority of them are still
# at v1. Cannot delete ways that are part of a relation. Does not delete
# ways of ways.
#
# Part of the "osmtools" suite of programs
# Originally written by Frederik Ramm <frederik@remote.org>; public domain

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Changeset;
use OsmApi;

if (scalar(@ARGV) != 1)
{
    print <<EOF;
usage: $0 {<changeset>|<comment>}

where 
  comment is the comment for the changeset to be created;
  if a changeset ID is given, re-use that changeset.

  way ids are read from stdin.
EOF
    exit;
}

my $full_cs=1;

my ($comment) = @ARGV;

my $ways=[];
while(<STDIN>)
{
    chomp;
    push(@$ways,$_);
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

die unless defined($current_cs);

my %wayver;
foreach my $n(@$ways)
{
    $wayver{$n}=1;
}

if ($full_cs)
{
    while(1) 
    {
        my $c="<osmChange version=\"0.6\">\n<delete if-unused=\"1\">\n";
        foreach my $n(keys %wayver)
        {
            $c .= "<way id=\"$n\" changeset=\"$current_cs\" version=\"" . $wayver{$n} . "\" />\n";
        }
        $c .= "</delete>\n</osmChange>\n";
        OsmApi::set_timeout(7200);
        my $resp = OsmApi::post("changeset/$current_cs/upload", $c);

        if (!$resp->is_success)
        {
            my $c = $resp->content;
            if ($c =~ /Version mismatch: Provided 1, server had: (\d+) of Way (\d+)/)
            {
                $wayver{$2}=$1;
                print STDERR "adjusted way $2 version to $1\n";
                next;
            }
            else
            {
                print STDERR "cannot upload changeset: ".$resp->status_line."\n";
                print STDERR $resp->content."\n";
                last;
            }
        }
        else
        {
            print STDERR $resp->content."\n";
            last;
        }
    }
}
else
{
    foreach my $n(@$ways)
    {
        my $resp = OsmApi::delete("way/$n", "<osm version='0.6'>\n<way id='$n' version='1' changeset='$current_cs' /></osm>");
        if ($resp->is_success)
        {
            printf(STDERR "deleted way $n\n");
            next;
        }
        my $c = $resp->content;
        if ($c =~ /already been deleted/)
        {
            printf(STDERR "already gone way $n\n");
            next;
        }
        if ($c =~ /Version mismatch: Provided 1, server had: (\d+)/)
        {
            my $v=$1;
            $resp = OsmApi::delete("way/$n", "<osm version='0.6'>\n<way id='$n' lat='0' lon='0' version='$v' changeset='$current_cs' /></osm>");
            if ($resp->is_success)
            {
                printf(STDERR "deleted way $n ($v)\n");
                next;
            }
            printf(STDERR "way $n ($v) cannot be deleted: %s\n", $resp->content);
        }
        else
        {
            printf(STDERR "way $n cannot be deleted: %s\n", $resp->content);
        }
    }
    
    Changeset::close($current_cs) unless ($current_cs eq $comment);
}

