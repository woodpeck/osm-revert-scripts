#!/usr/bin/perl

use strict;
use FindBin;
use lib $FindBin::Bin;
use OsmApi;

if (($ARGV[0] eq "request") && (scalar(@ARGV) == 1))
{
    request_tokens()
}
else
{
    print <<EOF;
Usage: 
  $0 request    request oauth2 tokens
EOF
    exit;
}

sub request_tokens
{
    if (OsmApi::check_oauth2_token("oauth2_token"))
    {
        print "Primary token is already received. Delete 'oauth2_token' from .osmtoolsrc to request it again.\n";
    }
    else
    {
        print "\n=== Requesting the primary token. ===\n\nLogin with your osm account that has full permissions.\n";
        OsmApi::request_oauth2_token("oauth2_token");
    }

    if (OsmApi::check_oauth2_token("oauth2_token_secondary"))
    {
        print "Secondary token is already received. Delete 'oauth2_token_secondary' from .osmtoolsrc to request it again.\n";
    }
    else
    {
        print "\n=== Requesting the secondary token. ===\n\nLogin with your bot/mechanical edit account.\nAltenatively, if you want to use only one account, interrupt the script.\n";
        OsmApi::request_oauth2_token("oauth2_token_secondary");
    }
}
