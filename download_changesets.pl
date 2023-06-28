#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long;
use URI::Escape;
use HTTP::Date qw(str2time time2isoz);
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

# metadata download phase

my %visited_changesets = ();
my $meta_output_dirname = "$output_dirname/meta";
mkdir $meta_output_dirname unless -d $meta_output_dirname;

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

    $to_date = format_date(time2isoz(str2time($bottom_created_at) + 1));
}

# changes download phase

foreach my $list_filename (reverse glob("$meta_output_dirname/*.osm"))
{
    print "read file $list_filename\n";
}

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

sub format_date
{
    my $date = shift;
    $date =~ s/ /T/;
    $date =~ tr/-://d;
    return $date;
}
