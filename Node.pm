#!/usr/bin/perl

package Node;

use strict;
use warnings;
use OsmApi;
use OsmData;
use URI::Escape;
use XML::Twig;

sub get_latest_changeset
{
    my $resp;

    $resp = OsmApi::get("user/details");
    if (!$resp->is_success)
    {
        print STDERR "cannot get current user details: ".$resp->status_line."\n";
        return undef;
    }

    my $uid = get_att_from_xml('user', 'id', $resp->content);
    if (!defined($uid))
    {
        print STDERR "cannot get current user id\n";
        return undef;
    }

    $resp = OsmApi::get("changesets?limit=1&user=".uri_escape($uid));
    if (!$resp->is_success)
    {
        print STDERR "cannot get current user's latest changeset: ".$resp->status_line."\n";
        return undef;
    }

    my $cid = get_att_from_xml('changeset', 'id', $resp->content);
    if (!defined($cid))
    {
        print STDERR "cannot get current user's latest changeset id\n";
        return undef;
    }
    return $cid;
}

sub get_latest_version
{
    my ($id) = @_;
    my ($resp, $twig);

    $resp = OsmApi::get("node/".uri_escape($id));
    if (!$resp->is_success)
    {
        print STDERR "cannot get node: ".$resp->status_line."\n";
        return undef;
    }

    my $version = get_att_from_xml('node', 'version', $resp->content);
    if (!defined($version))
    {
        print STDERR "cannot get node version\n";
        return undef;
    }
    return $version;
}

sub create
{
    my ($cid, $tags, $lat, $lon) = @_;

    my $body;
    open my $fh, '>', \$body;
    OsmData::print_fh_xml_header($fh);
    OsmData::print_fh_element($fh, OsmData::NODE, undef, undef, [
        $cid, undef, undef, undef, $tags, $lat * OsmData::SCALE, $lon * OsmData::SCALE
    ]);
    OsmData::print_fh_xml_footer($fh);
    close $fh;

    my $resp = OsmApi::put("node/create", $body);
    if (!$resp->is_success)
    {
        print STDERR "cannot create node: ".$resp->status_line."\n";
        return undef;
    }
    return $resp->content;
}

sub overwrite
{
    my ($cid, $id, $version, $tags, $lat, $lon) = @_;

    my $body;
    open my $fh, '>', \$body;
    OsmData::print_fh_xml_header($fh);
    OsmData::print_fh_element($fh, OsmData::NODE, $id, $version, [
        $cid, undef, undef, undef, $tags, $lat * OsmData::SCALE, $lon * OsmData::SCALE
    ]);
    OsmData::print_fh_xml_footer($fh);
    close $fh;

    my $resp = OsmApi::put("node/".uri_escape($id), $body);
    if (!$resp->is_success)
    {
        print STDERR "cannot overwrite node: ".$resp->status_line."\n";
        return undef;
    }
    return $resp->content;
}

# -----

sub get_att_from_xml
{
    my ($elt_name, $att_name, $content) = @_;

    my $twig = XML::Twig->new()->parse($content);
    return $twig->root->first_child($elt_name)->att($att_name);
}

1;
