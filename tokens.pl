#!/usr/bin/perl

use strict;
use FindBin;
use lib "$FindBin::Bin/lib";
use Getopt::Long;
use OsmApi;

if ($ARGV[0] eq "request")
{
    my $primary = 1;
    my $secondary = 1;
    my $scope;
    my $add_scope;
    my $remove_scope;
    my $no_scope;
    my $correct_options = GetOptions(
        "primary!" => \$primary,
        "secondary!" => \$secondary,
        "scope=s" => \$scope,
        "add-scope=s" => \$add_scope,
        "remove-scope=s" => \$remove_scope,
        "no-scope=s" => \$no_scope
    );

    if ($correct_options)
    {
        $scope = OsmApi::DEFAULT_SCOPE unless defined($scope);
        $scope = add_scope($scope, $add_scope) if defined($add_scope);
        $scope = remove_scope($scope, $remove_scope) if defined($remove_scope);
        $scope = remove_scope($scope, $no_scope) if defined($no_scope);

        if ($primary)
        {
            my $login_message = "Login with your osm account that has full permissions.\n";
            request_token($scope, "oauth2_token", "primary", $login_message);
        }
        if ($secondary)
        {
            my $login_message = "Login with your bot/mechanical edit account.\n";
            $login_message .= "Alternatively, if you want to use only one account, interrupt the script.\n" if $primary;
            request_token($scope, "oauth2_token_secondary", "secondary", $login_message);
        }
        exit;
    }
}

if ($ARGV[0] eq "check")
{
    my $user_details = 1;
    my $permissions = 0;
    my $introspect = 1;
    my $correct_options = GetOptions(
        "user-details!" => \$user_details,
        "permissions!" => \$permissions,
        "introspect!" => \$introspect
    );
    if ($correct_options)
    {
        check_tokens($user_details, $permissions, $introspect);
        exit;
    }
}

print <<EOF;
Usage: 
  $0 request <options>     request oauth2 tokens
  $0 check <options>       check details of stored tokens

request options:
  --no-primary                    don't request primary token
  --no-secondary                  don't request secondary token
  --scope <permissions>           request specified permissions
  --add-scope <permissions>       include permissions
  --remove-scope <permissions>    exclude permissions
  --no-scope <permissions>        exclude permissions

<permissions>:
  space-separated list of osm permissions like write_api

check options:
  --no-user-details               don't check user details
  --no-introspect                 don't check token with /oauth2/introspect endpoint
  --permissions                   check permissions with /api/0.6/permissions endpoint
EOF
exit;

sub add_scope
{
    my ($scope, $add_scope) = @_;

    my %permissions = map { $_ => 1 } split /\s+/, $scope;
    my @new_permissions = grep { !$permissions{$_} } split /\s+/, $add_scope;
    join " ", $scope, @new_permissions;
}

sub remove_scope
{
    my ($scope, $remove_scope) = @_;

    my %removed_permissions = map { $_ => 1 } split /\s+/, $remove_scope;
    join " ", grep { !$removed_permissions{$_} } split /\s+/, $scope;
}

sub request_token
{
    my ($scope, $token_name, $token_title, $login_message) = @_;

    if (OsmApi::check_oauth2_token($token_name))
    {
        print "The $token_title token is already received. Delete '$token_name' from .osmtoolsrc to request it again.\n";
    }
    else
    {
        print "\n=== Requesting the $token_title token. ===\n\n$login_message";
        OsmApi::request_oauth2_token($token_name, $scope);
    }
}

sub check_tokens
{
    if (OsmApi::check_oauth2_token("oauth2_token"))
    {
        print "Primary token details:\n";
        print_token_details(1, @_);
    }
    else
    {
        print "No primary token stored.\n\n";
    }

    if (OsmApi::check_oauth2_token("oauth2_token_secondary"))
    {
        print "Secondary token details:\n";
        print_token_details(0, @_);
    }
    else
    {
        print "No secondary token stored.\n\n";
    }
}

sub print_token_details
{
    use HTTP::Date qw(time2isoz);

    my ($primary, $user_details, $permissions, $introspect) = @_;
    print "- token: " . OsmApi::read_existing_oauth2_token($primary) . "\n";
    my $resp;

    if ($user_details)
    {
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
                    print "- user name: $1\n" if (/display_name="([^"]+)"/);
                    print "- user id: $1\n" if (/id="([^"]+)"/);
                }
                print "- moderator role\n" if (/<moderator/);
                print "- administrator role\n" if (/<administrator/);
            }
        }
    }

    if ($permissions)
    {
        $resp = OsmApi::get("permissions", undef, $primary);
        if (!$resp->is_success)
        {
            print "- failed to get permissions\n";
        }
        else
        {
            open my $fh, '<', \$resp->content;
            while (<$fh>)
            {
                if (/<permission/)
                {
                    print "- $1 permission\n" if (/name="([^"]+)"/);
                }
            }
        }
    }

    if ($introspect)
    {
        $resp = OsmApi::introspect_existing_oauth2_token($primary);
        if (!$resp->is_success)
        {
            print "- failed to introspect the token\n";
        }
        else
        {
            print "- token is inactive\n" if ($resp->content =~ /"active":false/);
            print "- permissions: $1\n" if ($resp->content =~ /"scope":"([^"]+)"/);
            print "- issued at: " . time2isoz($1) . "\n" if ($resp->content =~ /"iat":(\d+)/);
        }
    }

    print "\n";
}
