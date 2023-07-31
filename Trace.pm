#!/usr/bin/perl

package Trace;

use strict;
use warnings;
use OsmApi;

sub create
{
    my ($filename) = @_;

    my $description = "TODO set description";
    my $resp = OsmApi::post_multipart("gpx/create", [
        "file" => [$filename],
        "description" => $description,
    ]);
    if (!$resp->is_success)
    {
        print STDERR "cannot create trace: ".$resp->status_line."\n";
        return undef;
    }
    return $resp->content;
}

1;
