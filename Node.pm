#!/usr/bin/perl

package Node;

use strict;
use warnings;
use URI::Escape;
use XML::Twig;
use OsmApi;
use OsmData;

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

    $resp = OsmApi::get("nodes?nodes=".uri_escape($id)); # avoid 410 Gone on deleted elements
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

    my $body = get_request_body(undef, undef, [
        $cid, undef, undef, undef, $tags, $lat * OsmData::SCALE, $lon * OsmData::SCALE
    ]);
    my $resp = OsmApi::put("node/create", $body);
    if (!$resp->is_success)
    {
        print STDERR "cannot create node: ".$resp->status_line."\n";
        return undef;
    }
    return $resp->content;
}

sub delete
{
    my ($cid, $id, $version) = @_;

    my $body = get_request_body($id, $version, [
        $cid, undef, undef, undef, undef, 0, 0
    ]);
    my $resp = OsmApi::delete("node/".uri_escape($id), $body);
    if (!$resp->is_success)
    {
        print STDERR "cannot delete node: ".$resp->status_line."\n";
        return undef;
    }
    return $resp->content;
}

sub overwrite
{
    my ($cid, $id, $version, $to_version, $tags, $lat, $lon) = @_;
    my $resp;

    my ($visible, $edata);
    if (defined($to_version))
    {
        $resp = OsmApi::get("node/".uri_escape($id)."/".uri_escape($to_version));
        if (!$resp->is_success)
        {
            print STDERR "cannot get node version $to_version: ".$resp->status_line."\n";
            return undef;
        }
        my $data = OsmData::blank_data();
        OsmData::parse_elements_string($data, $resp->content);
        my $stored_edata = $data->{elements}[OsmData::NODE]{$id}{$to_version};
        my @tll;
        (undef, undef, undef, $visible, @tll) = @$stored_edata;
        if ($visible)
        {
            $edata = [
                $cid, undef, undef, undef, @tll
            ];
        }
        else
        {
            print "!($visible)\n";
            $edata = [
                $cid, undef, undef, undef, undef, 0, 0
            ];
        }
    }
    else
    {
        $visible = 1;
        $edata = [
            $cid, undef, undef, undef, $tags, $lat * OsmData::SCALE, $lon * OsmData::SCALE
        ];
    }

    my $body = get_request_body($id, $version, $edata);
    if ($visible)
    {
        $resp = OsmApi::put("node/".uri_escape($id), $body);
    }
    else
    {
        $resp = OsmApi::delete("node/".uri_escape($id), $body);
    }
    if (!$resp->is_success)
    {
        print STDERR "cannot overwrite node: ".$resp->status_line."\n";
        return undef;
    }
    return $resp->content;
}

# -----

sub get_request_body
{
    my ($id, $version, $edata) = @_;
    my $body;
    open my $fh, '>', \$body;
    OsmData::print_fh_xml_header($fh);
    OsmData::print_fh_element($fh, OsmData::NODE, $id, $version, $edata);
    OsmData::print_fh_xml_footer($fh);
    close $fh;
    return $body;
}

sub get_att_from_xml
{
    my ($elt_name, $att_name, $content) = @_;

    my $twig = XML::Twig->new()->parse($content);
    return $twig->root->first_child($elt_name)->att($att_name);
}

1;
