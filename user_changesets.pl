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
my $dirname;

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
  --directory <directory>

  either username or uid has to be supplied for the script to run
EOF
    exit;
}

GetOptions(
    "username|u=s" => \$username,
    "id|uid=i" => \$uid,
    "from|since=s" => \$since_date,
    "to=s" => \$to_date,
    "directory=s" => \$dirname
) or die("Error in command line arguments\n");

require_exactly_one_user_arg();

my $user_arg = get_user_arg();
$dirname = get_dirname() unless defined($dirname);
mkdir $dirname unless -d $dirname;

my $metadata_dirname = "$dirname/metadata";
mkdir $metadata_dirname unless -d $metadata_dirname;
UserChangesets::download_metadata($metadata_dirname, $user_arg, $since_date, $to_date);

if ($ARGV[1] eq "changes")
{
    my $changes_dirname = "$dirname/changes";
    mkdir $changes_dirname unless -d $changes_dirname;
    UserChangesets::download_changes($metadata_dirname, $changes_dirname, $since_date, $to_date);
}

sub require_exactly_one_user_arg
{
    if (defined($username))
    {
        die "both user name and id supplied, need to have only one of them" if (defined($uid));
    }
    else
    {
        die "neither user name nor id supplied, need to have one of them" unless (defined($uid));
    }
}

sub get_user_arg
{
    return "display_name=" . uri_escape($username) if (defined($username));
    return "user=" . uri_escape($uid);
}

sub get_dirname
{
    return "changesets_$username" if (defined($username));
    return "changesets_$uid";
}
