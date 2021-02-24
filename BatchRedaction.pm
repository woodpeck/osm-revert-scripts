#!/usr/bin/perl

# BatchRedaction.pm
# -----------------
#
# Implements redaction operations on the OSM API by reading element ids/versions from a file
#
# Part of the "osmtools" suite of programs
# public domain

package BatchRedaction;

use strict;
use warnings;
use OsmApi;

# -----------------------------------------------------------------------------
# Views specific versions of elements listed in a file
# Parameters: filename, request suffix
# request suffix is usually empty or ".json"
# Returns: 1 on success, undef on failure

sub view
{
    my ($filename, $suffix) = @_;
    $suffix //= "";
    open(FH, '<', $filename) or return undef;

    while(<FH>)
    {
        chomp;
        print "viewing $_\n";
        my $resp = OsmApi::get($_.$suffix);
        print $resp->content;
    }

    close(FH);
    return 1;
}

# -----------------------------------------------------------------------------
# Redacts specific versions of elements listed in a file
# Parameters: filename, Redaction ID
# Returns: 1 on success, undef on failure

sub apply
{
    my ($filename, $rid) = @_;
    open(FH, '<', $filename) or return undef;

    while(<FH>)
    {
        chomp;
        print "redacting $_\n";
        my $resp = OsmApi::post("$_/redact?redaction=$rid");

        if (!$resp->is_success)
        {
            my $m = $resp->content;
            $m =~ s/\s+/ /g;
            print STDERR "cannot redact $_: ".$resp->status_line.": $m\n";
            last;
        }
    }

    close(FH);
    return 1;
}

1;
