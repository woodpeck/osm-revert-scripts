#!/usr/bin/perl

use strict;
use FindBin;
use lib $FindBin::Bin;
use List::Util qw(uniqnum);
use Changeset;

my $dirname = "graph";
mkdir $dirname unless -d $dirname;

my %nodes_in_edges = read_graph_nodes_edges($dirname, "in");
my %nodes_out_edges = read_graph_nodes_edges($dirname, "out");

my @cids = sort { $a <=> $b } uniqnum keys(%nodes_in_edges), keys(%nodes_out_edges);
my %all_cids;
my %merged_edges;
foreach my $cid (@cids)
{
    $all_cids{$cid} = 1;
    if ($nodes_in_edges{$cid})
    {
        my @edges = @{$nodes_in_edges{$cid}};
        foreach my $edge (@edges)
        {
            my ($weight, $in_cid) = split ",", $edge;
            $all_cids{$in_cid} = 1;
            $merged_edges{$in_cid} = "$weight,$cid";
        }
    }
    if ($nodes_out_edges{$cid})
    {
        my @edges = @{$nodes_out_edges{$cid}};
        foreach my $edge (@edges)
        {
            my ($weight, $out_cid) = split ",", $edge;
            $all_cids{$out_cid} = 1;
            $merged_edges{$cid} = "$weight,$out_cid";
        }
    }
}

my $js_nodes;
my $js_links;
foreach my $cid (sort { $a <=> $b } keys(%all_cids))
{
    $js_nodes .= "{ id: $cid },\n";
    my $edge = $merged_edges{$cid};
    next unless defined($edge);
    my ($weight, $out_cid) = split ",", $edge;
    $js_links .= "{ source: $cid, target: $out_cid, weight: $weight },\n";
}

write_graph_html($dirname, $js_nodes, $js_links);

sub read_graph_nodes_edges($$)
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

sub write_graph_html($$$)
{
    my ($dirname, $js_nodes, $js_links) = @_;

    open my $fh, '>', "$dirname/graph.html";
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
const Graph = ForceGraph()
(document.getElementById('graph'))
    .graphData(gData)
    .linkWidth(({weight}) => 32*Math.log(weight)/Math.log(10000))
    .linkDirectionalArrowLength(6);
</script>
</body>
EOF
    close $fh;
}
