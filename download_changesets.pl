#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long;
use URI::Escape;
use OsmApi;

my $username;
my $uid;
my $since_date = "2001-01-01T00:00:00Z";
my $to_date;
my $output_dir;

GetOptions(
    "username|u=s" => \$username,
    "id|uid=i" => \$uid,
    "from|since=s" => \$since_date,
    "to=s" => \$to_date,
    "output=s" => \$output_dir
) or die("Error in command line arguments\n");

my $user_arg;
if (defined($username))
{
    if (defined($uid))
    {
        die "both user name and id supplied, need to have only one of them";
    }
    else
    {
        $user_arg = "display_name=" . uri_escape($username);
        $output_dir = "changesets_$user_arg" unless defined($output_dir);
    }
}
else
{
    if (defined($uid))
    {
        $user_arg = "user=" . uri_escape($uid);
        $output_dir = "changesets_$uid" unless defined($output_dir);
    }
    else
    {
        die "neither user name nor id supplied, need to have one of them";
    }
}

my $time_arg = "";
if (defined($to_date))
{
    $time_arg = "time=" . uri_escape($since_date) . "," . uri_escape($to_date);
}
else
{
    $time_arg = "time=" . uri_escape($since_date);
}

my $resp = OsmApi::get("changesets?$user_arg&$time_arg");
if (!$resp->is_success) {
    die "changeset metadata fetch failed: " . $resp->status_line;
}

print $resp->content;
