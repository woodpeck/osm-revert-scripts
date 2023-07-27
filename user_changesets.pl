#!/usr/bin/perl

use strict;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long;
use URI::Escape;
use UserChangesets;

my $username;
my $uid;
my $from_date = "2001-01-01";
my $to_date;
my $dirname;

my $correct_options = GetOptions(
    "username|u=s" => \$username,
    "id|uid=i" => \$uid,
    "from|since=s" => \$from_date,
    "to=s" => \$to_date,
    "directory|output=s" => \$dirname
);

my $from_timestamp = UserChangesets::parse_date($from_date);
die "unrecognized 'from' date format" unless defined($from_timestamp);
my $to_timestamp = UserChangesets::parse_date($to_date);
die "unrecognized 'to' date format" if defined($to_date) && !defined($to_timestamp);

if ($correct_options && ($ARGV[0] eq "download") && ($ARGV[1] eq "metadata") || ($ARGV[1] eq "changes"))
{
    require_exactly_one_user_arg();

    my $user_arg = get_user_arg();
    $dirname = get_dirname() unless defined($dirname);
    mkdir $dirname unless -d $dirname;

    my $metadata_dirname = "$dirname/metadata";
    mkdir $metadata_dirname unless -d $metadata_dirname;
    UserChangesets::download_metadata($metadata_dirname, $user_arg, $from_timestamp, $to_timestamp);

    if ($ARGV[1] eq "changes")
    {
        my $changes_dirname = "$dirname/changes";
        mkdir $changes_dirname unless -d $changes_dirname;
        UserChangesets::download_changes($metadata_dirname, $changes_dirname, $from_timestamp, $to_timestamp);
    }
}
elsif ($correct_options && ($ARGV[0] eq "count"))
{
    if (!defined($dirname))
    {
        require_exactly_one_user_arg();
        $dirname = get_dirname();
    }

    my $metadata_dirname = "$dirname/metadata";
    my $changes_dirname = "$dirname/changes";
    UserChangesets::count($metadata_dirname, $changes_dirname, $from_timestamp, $to_timestamp);
}
else
{
    print <<EOF;
Usage:
  $0 download metadata <options>
  $0 download changes <options>
  $0 count <options>

options:
  --username <username>
  --uid <uid>
  --from <date>
  --to <date>
  --directory <directory>

  download requires one of: username, uid
  count requires one of: username, uid, directory
EOF
    exit;
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
