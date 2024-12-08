#!/usr/bin/perl

use strict;
use FindBin;
use lib "$FindBin::Bin/lib";
use OsmApi;

if (($ARGV[0] eq "curl") && (scalar(@ARGV) >= 2))
{
    shift @ARGV;
    my $token = OsmApi::read_existing_oauth2_token(1);
    my $path = pop @ARGV;
    my $url = $OsmApi::prefs->{apiurl} . $path;
    exec "curl", "--oauth2-bearer", $token, @ARGV, $url;
}

if (($ARGV[0] eq "delete") && (scalar(@ARGV) == 2))
{
    my $path = $ARGV[1];
    OsmApi::delete($path, undef, 1);
    exit;
}

if (($ARGV[0] eq "get") && (scalar(@ARGV) == 2))
{
    my $path = $ARGV[1];
    OsmApi::get($path, undef, 1);
    exit;
}

if (($ARGV[0] eq "post") && (scalar(@ARGV) == 2))
{
    my $path = $ARGV[1];
    my $body = "";
    while(<STDIN>) { $body .= $_; }
    OsmApi::post($path, $body, 1);
    exit;
}

if (($ARGV[0] eq "put") && (scalar(@ARGV) == 2))
{
    my $path = $ARGV[1];
    my $body = "";
    while(<STDIN>) { $body .= $_; }
    OsmApi::put($path, $body, 1);
    exit;
}

print <<EOF;
Usage:
  $0 curl <path>                 run cURL with proper --oauth2-bearer and url
  $0 delete <path>               DELETE request
  $0 get <path>                  GET request
  $0 post <path> < input_file    POST request
  $0 put <path> < input_file     PUT request

<path> is relative to (server)/api/0.6/

Examples:
  get trace #23:
    $0 get gpx/23
  post a "test comment" comment for changeset #123 using cURL:
    $0 curl -d "text=test comment" changeset/123/comment
  upload a private trace file "filename.gpx" with description "some trace" using cURL:
    $0 curl -F "description=some trace" -F file=\@filename.gpx gpx/create

Enable debug output in .osmtoolsrc to see the results, for example:
  debug=1
  debug_response_headers=1
  debug_response_body=1
Or use cURL with its options, for example -v.
EOF
