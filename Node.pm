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
    my ($resp, $twig);

    $resp = OsmApi::get("user/details");
    if (!$resp->is_success)
    {
        print STDERR "cannot get current user details: ".$resp->status_line."\n";
        return undef;
    }

    $twig = XML::Twig->new()->parse($resp->content);
    my $uid = $twig->root->first_child('user')->att('id');
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

    $twig = XML::Twig->new()->parse($resp->content);
    my $cid = $twig->root->first_child('changeset')->att('id');
    if (!defined($cid))
    {
        print STDERR "cannot get current user's latest changeset id\n";
        return undef;
    }
    return $cid;
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

1;
