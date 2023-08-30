#!/usr/bin/perl

use strict;
use FindBin;
use lib $FindBin::Bin;
use Changeset;
use ChangesetGraph;

if (($ARGV[0] eq "add") && (scalar(@ARGV)==2))
{
    my ($command, $cid) = @ARGV;
    my $dirname = "graph";
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

    ChangesetGraph::generate($dirname);
    exit;
}

if (($ARGV[0] eq "redraw") && (scalar(@ARGV)==1))
{
    my $dirname = "graph";

    ChangesetGraph::generate($dirname);
    exit;
}

print <<EOF;
Usage:
  $0 add <id>    add changeset
  $0 redraw      redraw graph from added changesets
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
