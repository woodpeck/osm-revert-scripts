#!/usr/bin/perl

package Trace;

use strict;
use warnings;
use OsmApi;

# -----------------------------------------------------------------------------
# Creates a trace by uploading a file.
# Returns: new trace id, or undef in case of error (will write error to stderr)

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

sub delete
{
    my ($id) = @_;

    my $resp = OsmApi::delete("gpx/$id");

    if (!$resp->is_success)
    {
        print STDERR "cannot delete trace: ".$resp->status_line."\n";
        return undef;
    }
    return 1;
}

1;
