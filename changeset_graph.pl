#!/usr/bin/perl

use strict;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long;
use Changeset;
use ChangesetGraph;

my $dirname = "graph";
my $graph_cids = 1;
my $graph_users = 0;
my $graph_uids = 0;

my $correct_options = GetOptions(
    "directory|output=s" => \$dirname,
    "graph-cids!" => \$graph_cids,
    "graph-users!" => \$graph_users,
    "graph-uids!" => \$graph_uids,
);

if ($correct_options && ($ARGV[0] eq "add") && (scalar(@ARGV)==2))
{
    my ($command, $cid) = @ARGV;
    mkdir $dirname unless -d $dirname;

    my $metadata = Changeset::get($cid);
    die unless defined($metadata);
    write_node("$dirname/$cid.osm", $metadata);

    my $content = Changeset::download($cid);
    die unless defined($content);
    my @element_versions = Changeset::get_element_versions($content);

    my @previous_element_versions = Changeset::get_previous_element_versions(@element_versions);
    write_edges("$dirname/$cid.in", @previous_element_versions);

    my @next_element_versions = Changeset::get_next_element_versions(@element_versions);
    write_edges("$dirname/$cid.out", @next_element_versions);

    ChangesetGraph::generate($dirname, $graph_cids, $graph_users, $graph_uids);
    exit;
}

if ($correct_options && ($ARGV[0] eq "redraw") && (scalar(@ARGV)==1))
{
    ChangesetGraph::generate($dirname, $graph_cids, $graph_users, $graph_uids);
    exit;
}

print <<EOF;
Usage:
  $0 add <id> <options>               add changeset
  $0 redraw <options>                 redraw graph from added changesets

options:
  --directory <directory>             directory for changeset data and graph html file
  --graph-cids  | --no-graph-cids     [don't] show changeset ids on graph
  --graph-users | --no-graph-users    [don't] show usernames on graph
  --graph-uids  | --no-graph-uids     [don't] show user ids on graph
EOF

sub write_node($$)
{
    my ($filename, $metadata) = @_;
    open my $fh, '>', $filename;
    print $fh $metadata;
    close $fh;
}

sub write_edges($@)
{
    my $filename = shift;
    my @other_element_versions = @_;

    my $other_content = Changeset::download_elements(@other_element_versions);
    my @other_summary = Changeset::get_changeset_summary($other_content);
    open my $fh, '>', $filename;
    print $fh "$_\n" for @other_summary;
    close $fh;
}
