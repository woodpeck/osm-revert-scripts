#!/usr/bin/perl

use strict;
use FindBin;
use lib $FindBin::Bin;
use OsmApi;

if (($ARGV[0] eq "request") && (scalar(@ARGV) == 1))
{
    request_tokens();
}
elsif (($ARGV[0] eq "check") && (scalar(@ARGV) == 1))
{
    check_tokens();
}
else
{
    print <<EOF;
Usage: 
  $0 request    request oauth2 tokens
  $0 check      check user details of stored tokens
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

sub check_tokens
{
    if (OsmApi::check_oauth2_token("oauth2_token"))
    {
        print "Primary token details:\n";
        print_token_details(1);
    }
    else
    {
        print "No primary token stored.\n\n";
    }

    if (OsmApi::check_oauth2_token("oauth2_token_secondary"))
    {
        print "Secondary token details:\n";
        print_token_details();
    }
    else
    {
        print "No secondary token stored.\n\n";
    }
}

sub print_token_details
{
    use HTTP::Date qw(time2isoz);

    my ($primary) = @_;
    print "- token: " . OsmApi::read_existing_oauth2_token($primary) . "\n";
    my $resp;

    $resp = OsmApi::get("user/details", undef, $primary);
    if (!$resp->is_success)
    {
        print "- failed to get user details\n";
    }
    else
    {
        open my $fh, '<', \$resp->content;
        while (<$fh>)
        {
            if (/<user/)
            {
                print "- display name: $1\n" if (/display_name="([^"]+)"/);
                print "- id: $1\n" if (/id="([^"]+)"/);
            }
            print "- moderator role\n" if (/<moderator/);
            print "- administrator role\n" if (/<administrator/);
        }
    }

    ## get permissions without using oauth2 introspection endpoint:
    # $resp = OsmApi::get("permissions", undef, $primary);
    # if (!$resp->is_success)
    # {
    #     print "- failed to get permissions\n";
    # }
    # else
    # {
    #     open my $fh, '<', \$resp->content;
    #     while (<$fh>)
    #     {
    #         if (/<permission/)
    #         {
    #             print "- $1 permission\n" if (/name="([^"]+)"/);
    #         }
    #     }
    # }

    $resp = OsmApi::introspect_existing_oauth2_token($primary);
    if (!$resp->is_success)
    {
        print "- failed to introspect the token\n";
    }
    else
    {
        print "- permissions: $1\n" if ($resp->content =~ /"scope":"([^"]+)"/);
        print "- issued at: " . time2isoz($1) . "\n" if ($resp->content =~ /"iat":(\d+)/);
    }
    print "\n";
}
