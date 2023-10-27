#!/usr/bin/perl

package Node;

use strict;
use warnings;
use OsmApi;
use OsmData;

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
