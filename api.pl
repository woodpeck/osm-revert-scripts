#!/usr/bin/perl

use strict;
use FindBin;
use lib "$FindBin::Bin/lib";
use OsmApi;

if (($ARGV[0] eq "get") && (scalar(@ARGV) == 2))
{
    my $path = $ARGV[1];
    OsmApi::get($path, undef, 1);
    exit;
}

print <<EOF;
Usage:
  $0 get <path>    make get request

<path> is relative to (server)/api/0.6/. For example, this command gets trace #23:
  $0 get gpx/23

Enable debug output in .osmtoolsrc to see the results, for example:
  debug=1
  debug_response_headers=1
  debug_response_body=1
EOF
