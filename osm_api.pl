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

sub run_verb($&)
{
    my $verb = shift;
    my $sub = shift;
    if (($ARGV[0] eq $verb) && (scalar(@ARGV) == 2 || (scalar(@ARGV) == 3 && $ARGV[2] eq "-")))
    {
        my $path = $ARGV[1];
        my $body;
        if ($ARGV[2] eq "-")
        {
          $body = "";
          while(<STDIN>) { $body .= $_; }
        }
        &$sub($path, $body, 1);
        exit;
    }
}

run_verb "delete", \&OsmApi::delete;
run_verb "get", \&OsmApi::get;
run_verb "post", \&OsmApi::post;
run_verb "put", \&OsmApi::put;

print <<EOF;
Usage:
  $0 curl <curl options> <path>    run cURL with proper --oauth2-bearer and url
  $0 delete <path> [-]             DELETE request
  $0 get <path> [-]                GET request
  $0 post <path> [-]               POST request
  $0 put <path> [-]                PUT request

<path> is relative to (server)/api/0.6/

delete, get, post and put have an optional last argument "-" to read the request body from stdin,
otherwise an empty body is sent

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
