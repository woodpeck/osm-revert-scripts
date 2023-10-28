#!/usr/bin/perl

package Node;

use strict;
use warnings;
use URI::Escape;
use XML::Twig;
use OsmApi;
use OsmData;

our $data = OsmData::blank_data();

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

    my @elements = OsmData::parse_elements($data, $resp->content);
    my (undef, undef, $version) = @{$elements[0]};
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

sub modify
{
    my ($cid, $id, $version, $to_version, $reset, $tags, $lat, $lon) = @_;
    my $resp;

    my $edata;
    if (defined($to_version))
    {
        $edata = get_edata_for_version($id, $to_version);
    }
    elsif ($reset)
    {
        $edata = [$cid, undef, undef, 1, $tags, undef, undef];
    }
    else
    {
        $edata = get_edata_for_version($id, $version);
    }
    return unless defined($edata);

    $edata->[OsmData::LAT] = $lat * OsmData::SCALE if defined($lat);
    $edata->[OsmData::LON] = $lon * OsmData::SCALE if defined($lon);

    my $visible = update_and_extract_visible_from_edata($edata, $cid);
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
        print STDERR "cannot modify node: ".$resp->status_line."\n";
        return undef;
    }
    return $resp->content;
}

# -----

sub get_edata_for_version
{
    my ($id, $version) = @_;

    my $edata = get_stored_edata_copy($id, $version);
    if (!defined($edata))
    {
        my $resp = OsmApi::get("node/".uri_escape($id)."/".uri_escape($version));
        if (!$resp->is_success)
        {
            print STDERR "cannot get node version $version: ".$resp->status_line."\n";
            return undef;
        }
        OsmData::parse_elements($data, $resp->content);
        $edata = get_stored_edata_copy($id, $version);
    }
    if (!defined($edata))
    {
        print STDERR "cannot get data for node version $version\n";
        return undef;
    }
    return $edata;
}

sub get_stored_edata_copy
{
    my ($id, $version) = @_;

    my $stored_edata = $data->{elements}[OsmData::NODE]{$id}{$version};
    return unless defined($stored_edata);

    my @copied_edata = @$stored_edata;
    return \@copied_edata;
}

sub update_and_extract_visible_from_edata
{
    my ($edata, $cid) = @_;
    my $visible = $edata->[OsmData::VISIBLE];
    $edata->[OsmData::CHANGESET] = $cid;
    $edata->[OsmData::TIMESTAMP] = undef;
    $edata->[OsmData::UID] = undef;
    $edata->[OsmData::VISIBLE] = undef;
    $edata->[OsmData::LAT] = 0 unless $visible;
    $edata->[OsmData::LON] = 0 unless $visible;
    return $visible;
}

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
