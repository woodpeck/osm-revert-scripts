#!/usr/bin/perl

package ChangesetGraph;

use strict;
use warnings;
use List::Util qw(uniq);
use XML::Twig;

sub generate($$$$)
{
    my ($dirname, $show_ids, $show_users, $show_uids) = @_;
    my ($js_nodes, $js_links) = read_js_data($dirname);
    write_html($dirname, $show_ids, $show_users, $show_uids, $js_nodes, $js_links);
}

###

sub read_js_data($)
{
    my ($dirname) = @_;
    my %nodes;
    my %in_edges;
    my %out_edges;

    read_elements($dirname, \%nodes, \%in_edges);
    read_changesets($dirname, \%nodes);
    read_changeset_edges($dirname, "in", \%in_edges);
    read_changeset_edges($dirname, "out", \%out_edges);

    my @ids = sort {$a cmp $b} uniq keys(%nodes), keys(%in_edges), keys(%out_edges);
    my %all_ids;
    my %merged_nodes;
    my %merged_edges;
    foreach my $id (@ids)
    {
        $all_ids{$id} = 1;
        if ($in_edges{$id})
        {
            foreach my $edge (@{$in_edges{$id}})
            {
                my ($weight, $in_id, $in_uid, $in_user) = @$edge;
                $all_ids{$in_id} = 1;
                $merged_edges{$in_id}{$id} = $weight;
                $merged_nodes{$in_id} = [0, $in_uid, $in_user, ""];
            }
        }
        if ($out_edges{$id})
        {
            foreach my $edge (@{$out_edges{$id}})
            {
                my ($weight, $out_id, $out_uid, $out_user) = @$edge;
                $all_ids{$out_id} = 1;
                $merged_edges{$id}{$out_id} = $weight;
                $merged_nodes{$out_id} = [0, $out_uid, $out_user, ""];
            }
        }
    }
    foreach my $id (@ids)
    {
        if ($nodes{$id})
        {
            $merged_nodes{$id} = [1, @{$nodes{$id}}];
        }
    }

    my $js_nodes;
    foreach my $id (sort {$a cmp $b} keys(%all_ids))
    {
        my $node = $merged_nodes{$id};
        if ($node)
        {
            my ($selected, $uid, $user, $comment) = @$node;
            $js_nodes .= "{ id: '$id', selected: $selected, uid: $uid, user: ${\(to_js_string($user))}, comment: ${\(to_js_string($comment))} },\n";
        }
        else
        {
            $js_nodes .= "{ id: '$id', selected: 0 },\n";
        }
    }

    my $js_links;
    foreach my $in_id (sort {$a cmp $b} keys(%merged_edges))
    {
        my %out_edges = %{$merged_edges{$in_id}};
        foreach my $out_id (sort {$a cmp $b} keys(%out_edges))
        {
            my $weight = $out_edges{$out_id};
            $js_links .= "{ source: '$in_id', target: '$out_id', weight: $weight },\n";
        }
    }

    return $js_nodes, $js_links;
}

sub read_elements($$$)
{
    my ($dirname, $nodes, $in_edges) = @_;
    my %elements;

    foreach my $type ('node', 'way', 'relation')
    {
        my $t = substr($type, 0, 1);
        foreach my $filename (glob qq{"$dirname/${type}s/*.osm"})
        {
            next unless $filename =~ qr/(\d+)\.osm$/;
            my $eid = $1;
            my $twig = XML::Twig->new(keep_encoding => 1)->parsefile($filename);
            my $last_edge;

            foreach my $element ($twig->root->children) {
                my $version = $element->att('version');
                my $id = "${t}${eid}v${version}";
                $nodes->{$id} = [
                    $element->att('uid'),
                    $element->att('user'),
                    "",
                ];
                push @{$in_edges->{$id}}, [
                    1,
                    "c" . $element->att('changeset'),
                    $element->att('uid'),
                    $element->att('user'),
                ];
                push @{$in_edges->{$id}}, $last_edge if (defined($last_edge));
                $last_edge = [
                    1,
                    $id,
                    $element->att('uid'),
                    $element->att('user'),
                ];
            }
        }
    }
}

sub read_changesets($$)
{
    my ($dirname, $nodes) = @_;

    foreach my $filename (glob qq{"$dirname/changesets/*.osm"})
    {
        next unless $filename =~ qr/(\d+)\.osm$/;
        my $cid = $1;
        my $twig = XML::Twig->new(keep_encoding => 1)->parsefile($filename);
        my $changeset = $twig->root->first_child('changeset');
        my $comment_tag = $changeset->first_child('tag[@k="comment"]');
        my $comment = $comment_tag ? $comment_tag->att('v') : "";
        $nodes->{"c$cid"} = [
            $changeset->att('uid'),
            $changeset->att('user'),
            $comment,
        ];
    }
}

sub read_changeset_edges($$$)
{
    my ($dirname, $direction, $edges) = @_;

    foreach my $filename (glob qq{"$dirname/changesets/*.$direction"})
    {
        next unless $filename =~ qr/(\d+)\.${direction}$/;
        my $cid = $1;
        open my $fh, '<', $filename;
        chomp(my @lines = <$fh>);
        close $fh;
        push @{$edges->{"c$cid"}}, (map {
            my ($weight, $cid, $uid, $user) = split ",";
            [$weight, "c$cid", $uid, $user];
        } @lines);
    }
}

sub write_html($$$$$$)
{
    my ($dirname, $show_ids, $show_users, $show_uids, $js_nodes, $js_links) = @_;
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
${\(get_option_const('showIds', $show_ids))}
${\(get_option_const('showUsers', $show_users))}
${\(get_option_const('showUids', $show_uids))}
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

sub get_option_const($$)
{
    my ($name, $value) = @_;
    return "const $name = ${\($value ? 'true' : 'false')};";
}

sub to_js_string($)
{
    my ($s) = @_;
    $s =~ s/\\/\\\\/g;
    $s =~ s/'/\\'/g;
    return qq{'$s'};
}

1;
