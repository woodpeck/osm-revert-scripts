#!/usr/bin/perl

package ChangesetGraph;

use strict;
use warnings;
use List::Util qw(uniqnum);

sub generate($)
{
    my ($dirname) = @_;
    my ($js_nodes, $js_links) = read_js_data($dirname);
    write_html($dirname, $js_nodes, $js_links);
}

###

sub read_js_data($)
{
    my ($dirname) = @_;

    my %nodes_data = read_nodes_data($dirname);
    my %nodes_in_edges = read_nodes_edges($dirname, "in");
    my %nodes_out_edges = read_nodes_edges($dirname, "out");

    my @cids = sort { $a <=> $b } uniqnum keys(%nodes_data), keys(%nodes_in_edges), keys(%nodes_out_edges);
    my %all_cids;
    my %merged_nodes;
    my %merged_edges;
    foreach my $cid (@cids)
    {
        $all_cids{$cid} = 1;
        if ($nodes_in_edges{$cid})
        {
            my @edges = @{$nodes_in_edges{$cid}};
            foreach my $edge (@edges)
            {
                my ($weight, $in_cid, $in_uid, $in_user) = split ",", $edge;
                $all_cids{$in_cid} = 1;
                $merged_edges{$in_cid}{$cid} = $weight;
                $merged_nodes{$in_cid} = "0,$in_uid,$in_user";
            }
        }
        if ($nodes_out_edges{$cid})
        {
            my @edges = @{$nodes_out_edges{$cid}};
            foreach my $edge (@edges)
            {
                my ($weight, $out_cid, $out_uid, $out_user) = split ",", $edge;
                $all_cids{$out_cid} = 1;
                $merged_edges{$cid}{$out_cid} = $weight;
                $merged_nodes{$out_cid} = "0,$out_uid,$out_user";
            }
        }
    }
    foreach my $cid (@cids)
    {
        if ($nodes_data{$cid})
        {
            $merged_nodes{$cid} = "1," . $nodes_data{$cid};
        }
    }

    my $js_nodes;
    foreach my $cid (sort { $a <=> $b } keys(%all_cids))
    {
        my $node = $merged_nodes{$cid};
        if ($node)
        {
            my ($selected, $uid, $user) = split ",", $node;
            $user =~ s/"/\\"/g;
            $js_nodes .= qq#{ id: $cid, selected: $selected, uid: $uid, user: "$user" },\n#;
        }
        else
        {
            $js_nodes .= "{ id: $cid, selected: 0 },\n";
        }
    }

    my $js_links;
    foreach my $in_cid (sort { $a <=> $b } keys(%merged_edges))
    {
        my %out_edges = %{$merged_edges{$in_cid}};
        foreach my $out_cid (sort { $a <=> $b } keys(%out_edges))
        {
            my $weight = $out_edges{$out_cid};
            $js_links .= "{ source: $in_cid, target: $out_cid, weight: $weight },\n";
        }
    }

    return $js_nodes, $js_links;
}

sub read_nodes_data($)
{
    my ($dirname) = @_;
    my %nodes_data;

    foreach my $filename (glob qq{"$dirname/*.osm"})
    {
        next unless $filename =~ qr/(\d+)\.osm$/;
        my $cid = $1;
        open my $fh, '<', $filename;
        while (<$fh>)
        {
            next unless /<changeset/;
            /user="([^"]*)"/;
            my $user = $1;
            /uid="([^"]*)"/;
            my $uid = $1;
            $nodes_data{$cid} = "$uid,$user";
            last;
        }
        close $fh;
    }
    return %nodes_data;
}

sub read_nodes_edges($$)
{
    my ($dirname, $direction) = @_;
    my %nodes_edges;

    foreach my $filename (glob qq{"$dirname/*.$direction"})
    {
        next unless $filename =~ qr/(\d+)\.${direction}$/;
        my $cid = $1;
        open my $fh, '<', $filename;
        chomp(my @lines = <$fh>);
        close $fh;
        $nodes_edges{$cid} = \@lines;
    }
    return %nodes_edges;
}

sub write_html($$$)
{
    my ($dirname, $js_nodes, $js_links) = @_;
    my $fh;

    open $fh, '<', $FindBin::Bin . "/graph.js";
    my $js_draw_graph = do { local $/; <$fh> };
    close $fh;

    open $fh, '>', "$dirname/index.html";
    print $fh <<EOF;
<head>
<style> body { margin: 0; } </style>
<script src="https://unpkg.com/force-graph\@1.43.3/dist/force-graph.min.js"></script>
</head>
<body>
<div id="graph"></div>
<script>
const gData = {
nodes: [
$js_nodes],
links: [
$js_links],
};

$js_draw_graph</script>
</body>
EOF
    close $fh;
}

1;
