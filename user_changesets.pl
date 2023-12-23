#!/usr/bin/perl

use strict;
use FindBin;
use lib "$FindBin::Bin/lib";
use Getopt::Long;
use List::Util qw(pairmap);
use URI::Escape;
use UserChangesets;
use UserChangesetsList;

my %show_options_data = (
    close_time => "show changeset close time",
    operation_counts => "show create/modify/delete counts",
    element_counts => "show node/way/relation counts",
    operation_x_element_counts => "show operation per element type counts",
    target_upper_bound => "show upper bound of target matches",
);

my ($username, $uid);
my $from_date = "2001-01-01";
my $to_date;
my ($dirname, $metadata_dirname, $changes_dirname, $previous_dirname, $store_dirname);
my $output_filename;
my %show_options = pairmap { $a => 0 } %show_options_data;
my $target_delete_tag;

my $correct_options = GetOptions(
    "username|u=s" => \$username,
    "id|uid=i" => \$uid,
    "from|since=s" => \$from_date,
    "to=s" => \$to_date,
    "directory|dirname|output=s" => \$dirname,
    "metadata-directory|metadata-dirname=s" => \$metadata_dirname,
    "changes-directory|changes-dirname=s" => \$changes_dirname,
    "previous-directory|previous-dirname=s" => \$previous_dirname,
    "store-directory|store-dirname=s" => \$store_dirname,
    "output-filename=s" => \$output_filename,
    (pairmap { $a =~ tr/_/-/; "show-$a!" => \$b } %show_options),
    "target-delete-tag=s" => \$target_delete_tag,
);

my $from_timestamp = UserChangesets::parse_date($from_date);
die "unrecognized 'from' date format" unless defined($from_timestamp);
my $to_timestamp = UserChangesets::parse_date($to_date);
die "unrecognized 'to' date format" if defined($to_date) && !defined($to_timestamp);
UserChangesets::print_date_range($from_timestamp, $to_timestamp);

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
    $previous_dirname //= "$dirname/previous";
    $store_dirname //= "$dirname/.store";
    $output_filename //= "$dirname/index.html";
}

if ($correct_options && ($ARGV[0] eq "download") && ($ARGV[1] eq "metadata") || ($ARGV[1] eq "changes") || ($ARGV[1] eq "previous"))
{
    die "parameters required: one of (display_name, uid)" unless defined($user_arg) && defined($dirname);
    UserChangesets::download_metadata($metadata_dirname, $user_arg, $from_timestamp, $to_timestamp);
    if (($ARGV[1] eq "changes") || ($ARGV[1] eq "previous"))
    {
        UserChangesets::download_changes($metadata_dirname, $changes_dirname, $from_timestamp, $to_timestamp);
        if ($ARGV[1] eq "previous")
        {
            UserChangesets::download_previous($metadata_dirname, $changes_dirname, $previous_dirname, $store_dirname, $from_timestamp, $to_timestamp);
        }
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
    die "show-operation-counts require one of: (display_name, uid, directory, changes-directory)" if $show_options{operation_counts} && !defined($changes_dirname);
    die "show-element-counts require one of: (display_name, uid, directory, changes-directory)" if $show_options{element_counts} && !defined($changes_dirname);
    die "show-operation-x-element-counts require one of: (display_name, uid, directory, changes-directory)" if $show_options{operation_x_element_counts} && !defined($changes_dirname);
    die "target-delete-tag require one of: (display_name, uid, directory, changes-directory)" if defined($target_delete_tag) && !defined($changes_dirname);
    UserChangesetsList::list(
        $metadata_dirname, $changes_dirname, $store_dirname, $from_timestamp, $to_timestamp, $output_filename,
        \%show_options, $target_delete_tag
    );
    exit;
}

print <<EOF;
Usage:
  $0 download metadata <options>         download changeset metadata like dates, tags, bboxes
  $0 download changes <options>          download modified elements in .osc format
  $0 download previous <options>         download previous versions of modified elements
  $0 count <options>                     report number of downloaded changesets
  $0 list <options>                      generate a html file with a list of changesets

options:
  --username <username>
  --uid <uid>
  --from <date>
  --to <date>
  --directory <directory>                derived from --username or --uid if not provided
  --metadata-directory <directory>       derived from --directory if not provided
  --changes-directory <directory>        derived from --directory if not provided
  --previous-directory <directory>       derived from --directory if not provided
  --store-directory <directory>          derived from --directory if not provided
  --output-filename <filename>           derived from --directory if not provided
EOF
for (sort keys %show_options_data)
{
    my $o = $_; $o =~ tr/_/-/;
    printf "  %-38s %s\n", "--show-$o", $show_options_data{$_};
}
print <<EOF;
  --target-delete-tag <tag key>          for list command: show changes matching tag deletion counts
EOF
