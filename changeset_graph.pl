#!/usr/bin/perl

use strict;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long;
use OsmApi;
use Changeset;
use ChangesetGraph;

my $dirname = "graph";
my $graph_ids = 1;
my $graph_users = 0;
my $graph_uids = 0;

my $correct_options = GetOptions(
    "directory|output=s" => \$dirname,
    "graph-ids!" => \$graph_ids,
    "graph-users!" => \$graph_users,
    "graph-uids!" => \$graph_uids,
);

my %types = ("changeset" => 1, "node" => 1, "way" => 1, "relation" => 1);

if ($correct_options && ($ARGV[0] eq "add") && $types{$ARGV[1]} && (scalar(@ARGV)==3))
{
    my ($command, $type, $id) = @ARGV;
    mkdir $dirname unless -d $dirname;

    if ($type eq "changeset")
    {
        my $subdirname = "$dirname/changesets";
        mkdir $subdirname unless -d $subdirname;

        my $metadata = Changeset::get($id);
        die unless defined($metadata);
        write_file("$subdirname/$id.osm", $metadata);

        my $content = Changeset::download($id);
        die unless defined($content);
        my @element_versions = Changeset::get_element_versions($content);

        my @previous_element_versions = Changeset::get_previous_element_versions(@element_versions);
        write_edges("previous", "$subdirname/$id.in", @previous_element_versions);

        my @next_element_versions = Changeset::get_next_element_versions(@element_versions);
        write_edges("next", "$subdirname/$id.out", @next_element_versions);
    }
    else
    {
        my $subdirname = "$dirname/${type}s";
        mkdir $subdirname unless -d $subdirname;

        my $resp = OsmApi::get("$type/$id/history?show_redactions=true", "", 1);
        if (!$resp->is_success)
        {
            print STDERR "history of $type $id cannot be retrieved: ".$resp->status_line."\n";
            die;
        }
        write_file("$subdirname/$id.osm", $resp->content());
    }

    ChangesetGraph::generate($dirname, $graph_ids, $graph_users, $graph_uids);
    exit;
}

if ($correct_options && ($ARGV[0] eq "remove") && $types{$ARGV[1]} && (scalar(@ARGV)==3))
{
    my ($command, $type, $id) = @ARGV;
    mkdir $dirname unless -d $dirname;

    if ($type eq "changeset")
    {
        my $subdirname = "$dirname/changesets";
        unlink "$subdirname/$id.osm";
        unlink "$subdirname/$id.in";
        unlink "$subdirname/$id.out";
    }
    else
    {
        my $subdirname = "$dirname/${type}s";
        unlink "$subdirname/$id.osm";
    }

    ChangesetGraph::generate($dirname, $graph_ids, $graph_users, $graph_uids);
    exit;
}

if ($correct_options && ($ARGV[0] eq "redraw") && (scalar(@ARGV)==1))
{
    ChangesetGraph::generate($dirname, $graph_ids, $graph_users, $graph_uids);
    exit;
}

print <<EOF;
Usage:
  $0 add <type> <id> <options>        add changeset to graph
  $0 remove <type> <id> <options>     remove changeset from graph
  $0 redraw <options>                 redraw graph from added changesets

type:
  changeset
  node
  way
  relation

options:
  --directory <directory>             directory for changeset/element data and graph html file
  --graph-ids   | --no-graph-ids      [don't] show changeset/element ids on graph
  --graph-users | --no-graph-users    [don't] show usernames on graph
  --graph-uids  | --no-graph-uids     [don't] show user ids on graph
EOF

sub write_file($$)
{
    my ($filename, $metadata) = @_;
    open my $fh, '>', $filename;
    print $fh $metadata;
    close $fh;
}

sub write_edges($$@)
{
    my $relation = shift;
    my $filename = shift;
    my @other_element_versions = @_;

    my $other_content = Changeset::download_elements($relation, @other_element_versions);
    my @other_summary = Changeset::get_changeset_summary($other_content);
    open my $fh, '>', $filename;
    print $fh "$_\n" for @other_summary;
    close $fh;
}
