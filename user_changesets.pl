#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long;
use URI::Escape;
use UserChangesets;

my $username;
my $uid;
my $since_date = "2001-01-01T00:00:00Z";
my $to_date;
my $output_dirname;

if ((scalar(@ARGV) < 2) || ($ARGV[0] ne "download") || (($ARGV[1] ne "metadata") && ($ARGV[1] ne "changes")))
{
    print <<EOF;
Usage:
  $0 download metadata <options>
  $0 download changes <options>

options:
  --username <username>
  --uid <uid>
  --from <date>
  --to <date>
  --output <directory>

  either username or uid has to be supplied for the script to run
EOF
    exit;
}

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

my $metadata_output_dirname = "$output_dirname/metadata";
mkdir $metadata_output_dirname unless -d $metadata_output_dirname;
UserChangesets::download_metadata($metadata_output_dirname, $user_arg, $since_date, $to_date);

if ($ARGV[1] eq "changes")
{
    my $changes_output_dirname = "$output_dirname/changes";
    mkdir $changes_output_dirname unless -d $changes_output_dirname;
    UserChangesets::download_changes($metadata_output_dirname, $changes_output_dirname, $since_date, $to_date);
}
