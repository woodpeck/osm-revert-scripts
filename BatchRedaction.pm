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
        my $resp = OsmApi::get($_.$suffix);
        my $code = $resp->code;
        if ($resp->is_success) {
            print "# $_ not redacted\n\n";
            print $resp->content;
            print "\n";
        } elsif ($code == 404) {
            print "# $_ not found\n\n";
        } elsif ($code == 403) {
            my $resp2 = OsmApi::get($_.$suffix."?show_redactions=true");
            if ($resp2->is_success) {
                print "# $_ redacted and can be revealed\n\n";
                print $resp2->content;
                print "\n";
            } else {
                print "# $_ redacted and cannot be revealed\n\n";
            }
        } else {
            print "# $_ encountered unknown error\n\n";
        }
    }

    close(FH);
    return 1;
}

# -----------------------------------------------------------------------------
# Redacts specific versions of elements listed in a file
# Parameters: filename, Redaction ID
# use empty redaction id to unredact
# Returns: 1 on success, undef on failure
# stops on the first failed redaction

sub apply
{
    my ($filename, $rid) = @_;
    my $state = 1;
    open(FH, '<', $filename) or return undef;

    while(<FH>)
    {
        chomp;
        print "redacting $_\n";
        my $path = "$_/redact";
        $path .= "?redaction=$rid" if defined $rid;
        my $resp = OsmApi::post($path);

        if (!$resp->is_success)
        {
            my $m = $resp->content;
            $m =~ s/\s+/ /g;
            print STDERR "cannot redact $_: ".$resp->status_line.": $m\n";
            $state = undef;
            last;
        }
    }

    close(FH);
    return $state;
}

1;
