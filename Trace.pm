#!/usr/bin/perl

package Trace;

use strict;
use warnings;
use OsmApi;

sub create
{
    my ($filename, $description, $tags, $visibility) = @_;

    my $resp = OsmApi::post_multipart("gpx/create", [
        "file" => [$filename],
        "description" => $description,
        "tags" => $tags,
        "visibility" => $visibility,
    ]);
    if (!$resp->is_success)
    {
        print STDERR "cannot create trace: ".$resp->status_line."\n";
        return undef;
    }
    return $resp->content;
}

1;
