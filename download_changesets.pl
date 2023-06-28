#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long;
use URI::Escape;
use HTTP::Date qw(str2time time2isoz);
use OsmApi;
use Changeset;

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

$since_date = format_date($since_date);
$to_date = format_date($to_date) if defined($to_date);

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

# existing metadata check phase

my $updated_to_date = $to_date;
my %visited_changesets = ();
my $meta_output_dirname = "$output_dirname/meta";
mkdir $meta_output_dirname unless -d $meta_output_dirname;

foreach my $list_filename (reverse glob("$meta_output_dirname/*.osm"))
{
    my $bottom_created_at;
    iterate_over_changesets($list_filename, sub {
        my ($id, $created_at, $closed_at) = @_;
        $bottom_created_at = $created_at;
        if (!$visited_changesets{$id}) {
            $visited_changesets{$id} = 1;
        }
    });
    $updated_to_date = update_to_date($updated_to_date, $bottom_created_at) if defined($bottom_created_at);
}

# new metadata download phase

while (1)
{
    my $time_arg = "";
    if (defined($updated_to_date))
    {
        $time_arg = "time=" . uri_escape($since_date) . "," . uri_escape($updated_to_date);
    }
    else
    {
        $time_arg = "time=" . uri_escape($since_date);
    }

    my $resp = OsmApi::get("changesets?$user_arg&$time_arg");
    if (!$resp->is_success)
    {
        die "changeset metadata fetch failed: " . $resp->status_line;
    }

    my $list = $resp->content;
    my ($top_created_at, $bottom_created_at);
    my $new_changesets_count = 0;

    iterate_over_changesets(\$list, sub {
        my ($id, $created_at, $closed_at) = @_;
        $bottom_created_at = $created_at;
        $top_created_at = $created_at unless defined($top_created_at);
        if (!$visited_changesets{$id}) {
            $new_changesets_count++;
            $visited_changesets{$id} = 1;
        }
    });

    if (defined($top_created_at))
    {
        $_ = $top_created_at;
        my $list_filename = "$meta_output_dirname/$_.osm";
        open(my $list_fh, '>', $list_filename) or die "can't open changeset list file '$list_filename' for writing";
        print $list_fh $list;
        close $list_fh;
    }

    last if $new_changesets_count == 0;

    $updated_to_date = update_to_date($updated_to_date, $bottom_created_at);
}

# changes download phase

my $changes_output_dirname = "$output_dirname/changes";
mkdir $changes_output_dirname unless -d $changes_output_dirname;
foreach my $list_filename (reverse glob("$meta_output_dirname/*.osm"))
{
    my $since_timestamp = str2time($since_date);
    my $to_timestamp = str2time($to_date);
    iterate_over_changesets($list_filename, sub {
        my ($id, $created_at, $closed_at) = @_;
        my $changes_filename = "$changes_output_dirname/$id.osc";
        return if -f $changes_filename;
        return if (str2time($closed_at) < $since_timestamp);
        return if (defined($to_timestamp) && str2time($created_at) >= $to_timestamp);
        my $osc = Changeset::download($id) or die "failed to download changeset $id";
        open(my $fh, '>', $changes_filename) or die "can't open changes file '$changes_filename' for writing";
        print $fh $osc;
        close $fh;
    });
}

#

sub iterate_over_changesets
{
    my ($list_source, $handler) = @_;

    open my $list_fh, '<', $list_source;
    while (<$list_fh>)
    {
        next unless /<changeset/;
        /id="(\d+)"/;
        my $id = $1;
        /created_at="([^"]*)"/;
        my $created_at = $1;
        /closed_at="([^"]*)"/;
        my $closed_at = $1;
        next unless defined($id) && defined($created_at) && defined($closed_at);
        $handler -> ($id, format_date($created_at), format_date($closed_at));
    }
    close $list_fh;
}

sub update_to_date
{
    my ($to_date, $bottom_created_at) = @_;
    my $new_timestamp = str2time($bottom_created_at) + 1;

    if (!defined($to_date) || $new_timestamp < str2time($to_date))
    {
        return format_date(time2isoz($new_timestamp));
    }
    else
    {
        return $to_date;
    }
}

sub format_date
{
    my $date = shift;
    $date =~ s/ /T/;
    $date =~ tr/-://d;
    return $date;
}
