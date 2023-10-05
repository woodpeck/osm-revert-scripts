#!/usr/bin/perl

use strict;
use FindBin;
use lib $FindBin::Bin;
use File::Path qw(make_path);
use Getopt::Long;
use URI::Escape;
use UserChangesets;

my ($username, $uid);
my $from_date = "2001-01-01";
my $to_date;
my ($dirname, $metadata_dirname, $changes_dirname);
my $output_filename;

my $correct_options = GetOptions(
    "username|u=s" => \$username,
    "id|uid=i" => \$uid,
    "from|since=s" => \$from_date,
    "to=s" => \$to_date,
    "directory|dirname|output=s" => \$dirname,
    "metadata-directory|metadata-dirname=s" => \$metadata_dirname,
    "changes-directory|changes-dirname=s" => \$changes_dirname,
    "output-filename=s" => \$output_filename
);

my $from_timestamp = UserChangesets::parse_date($from_date);
die "unrecognized 'from' date format" unless defined($from_timestamp);
my $to_timestamp = UserChangesets::parse_date($to_date);
die "unrecognized 'to' date format" if defined($to_date) && !defined($to_timestamp);

if (defined($username) && defined($uid))
{
    die "both user name and id supplied, can only work with one of them";
}

my $user_arg;
if (defined($username))
{
    $user_arg //= "display_name=".uri_escape($username);
    $dirname //= "changesets_$username";
}
elsif (defined($uid))
{
    $user_arg //= "user=".uri_escape($uid);
    $dirname //= "changesets_$uid";
}
if (defined($dirname))
{
    $metadata_dirname //= "$dirname/metadata";
    $changes_dirname //= "$dirname/changes";
    $output_filename //= "$dirname/index.html";
}

if ($correct_options && ($ARGV[0] eq "download") && ($ARGV[1] eq "metadata") || ($ARGV[1] eq "changes"))
{
    die "parameters required: one of (display_name, uid)" unless defined($user_arg) && defined($dirname);

    make_path($metadata_dirname);
    UserChangesets::download_metadata($metadata_dirname, $user_arg, $from_timestamp, $to_timestamp);

    if ($ARGV[1] eq "changes")
    {
        make_path($changes_dirname);
        UserChangesets::download_changes($metadata_dirname, $changes_dirname, $from_timestamp, $to_timestamp);
    }
    exit;
}

if ($correct_options && ($ARGV[0] eq "count"))
{
    die "parameters required: one of (display_name, uid, directory, metadata-directory)" unless defined($metadata_dirname);
    UserChangesets::count($metadata_dirname, $changes_dirname, $from_timestamp, $to_timestamp);
    exit;
}

if ($correct_options && ($ARGV[0] eq "list"))
{
    die "parameters required: one of (display_name, uid, directory) or both (metadata-directory, output-filename)" unless defined($metadata_dirname) && defined($output_filename);
    UserChangesets::list($output_filename, $metadata_dirname, $from_timestamp, $to_timestamp);
    exit;
}

print <<EOF;
Usage:
  $0 download metadata <options>
  $0 download changes <options>
  $0 count <options>                report number of downloaded changesets
  $0 list <options>                 generate a html file with a list of changesets

options:
  --username <username>
  --uid <uid>
  --from <date>
  --to <date>
  --directory <directory>           derived from --username or --uid if not provided
  --metadata-directory <directory>  derived from --directory if not provided
  --changes-directory <directory>   derived from --directory if not provided
  --output-filename <filename>      derived from --directory if not provided
EOF
