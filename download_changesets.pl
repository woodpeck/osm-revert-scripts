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
my $output_dirname;

GetOptions(
    "username|u=s" => \$username,
    "id|uid=i" => \$uid,
    "from|since=s" => \$since_date,
    "to=s" => \$to_date,
    "output=s" => \$output_dirname
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
        $output_dirname = "changesets_$username" unless defined($output_dirname);
    }
}
else
{
    if (defined($uid))
    {
        $user_arg = "user=" . uri_escape($uid);
        $output_dirname = "changesets_$uid" unless defined($output_dirname);
    }
    else
    {
        die "neither user name nor id supplied, need to have one of them";
    }
}

mkdir $output_dirname unless -d $output_dirname;

while (1)
{
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

    $_ = $since_date;
    tr/-://d;
    my $list_filename = "$output_dirname/$_.xml";
    my $list_fh;
    open($list_fh, '>', $list_filename) or die "can't open changeset list file '$list_filename' for writing";
    print $list_fh $resp->content;
    close $list_fh;

    last;
}
