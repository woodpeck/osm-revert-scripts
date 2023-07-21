#!/usr/bin/perl

package UserChangesets;

use strict;
use warnings;
use URI::Escape;
use HTTP::Date qw(str2time time2isoz);
use OsmApi;
use Changeset;

# -----------------------------------------------------------------------------
# Downloads given user's changeset metadata (open/close dates, bboxes, tags, ...)
# Parameters: metadata directory for output, user argument, from date, to date
# user argument is either display_name=... or user=... with urlencoded display name or id

sub download_metadata
{
    my ($metadata_dirname, $user_arg, $since_date, $to_date) = @_;
    $since_date = format_date($since_date);
    $to_date = format_date($to_date) if defined($to_date);
    my $updated_to_date = $to_date;
    my %visited_changesets = ();
    my $download_more = 1;

    # existing metadata check phase

    foreach my $list_filename (reverse glob("$metadata_dirname/*.osm"))
    {
        my $bottom_created_at;
        iterate_over_changesets($list_filename, sub {
            my ($id, $created_at, $closed_at) = @_;
            $bottom_created_at = $created_at;
            if (!$visited_changesets{$id}) {
                $visited_changesets{$id} = 1;
            }
        });
        ($updated_to_date, $download_more) = update_to_date($updated_to_date, $bottom_created_at) if defined($bottom_created_at);
    }

    # new metadata download phase

    while ($download_more)
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
            my $list_filename = "$metadata_dirname/$_.osm";
            open(my $list_fh, '>', $list_filename) or die "can't open changeset list file '$list_filename' for writing";
            print $list_fh $list;
            close $list_fh;
        }

        last if $new_changesets_count == 0;

        ($updated_to_date) = update_to_date($updated_to_date, $bottom_created_at);
    }
}

# -----------------------------------------------------------------------------
# Downloads changeset changes (elements) matching provided metadata and date rande
# Parameters: metadata directory to be scanned, changes directory for output, from date, to date

sub download_changes
{
    my ($metadata_dirname, $changes_dirname, $since_date, $to_date) = @_;

    foreach my $list_filename (reverse glob("$metadata_dirname/*.osm"))
    {
        my $since_timestamp = str2time($since_date);
        my $to_timestamp = str2time($to_date);
        iterate_over_changesets($list_filename, sub {
            my ($id, $created_at, $closed_at) = @_;
            my $changes_filename = "$changes_dirname/$id.osc";
            return if -f $changes_filename;
            return if (str2time($closed_at) < $since_timestamp);
            return if (defined($to_timestamp) && str2time($created_at) >= $to_timestamp);
            my $osc = Changeset::download($id) or die "failed to download changeset $id";
            open(my $fh, '>', $changes_filename) or die "can't open changes file '$changes_filename' for writing";
            print $fh $osc;
            close $fh;
        });
    }
}

# -----------------------------------------------------------------------------
# Count downloaded changesets inside given date range
# Parameters: metadata directory, changes directory, from date, to date

sub count
{
    my ($metadata_dirname, $changes_dirname, $since_date, $to_date) = @_;
    my %visited_changesets = ();
    my $metadata_count = 0;
    my $changes_count = 0;

    foreach my $list_filename (reverse glob("$metadata_dirname/*.osm"))
    {
        my $since_timestamp = str2time($since_date);
        my $to_timestamp = str2time($to_date);
        iterate_over_changesets($list_filename, sub {
            my ($id, $created_at, $closed_at) = @_;
            return if (str2time($closed_at) < $since_timestamp);
            return if (defined($to_timestamp) && str2time($created_at) >= $to_timestamp);
            return if $visited_changesets{$id};
            $visited_changesets{$id} = 1;
            $metadata_count++;
            my $changes_filename = "$changes_dirname/$id.osc";
            $changes_count++ if -e $changes_filename;
        });
    }

    print "downloaded $metadata_count changeset metadata records\n";
    print "downloaded $changes_count changeset change files\n";
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

sub update_to_date
{
    my ($to_date, $bottom_created_at) = @_;
    my $new_timestamp = str2time($bottom_created_at) + 1;
    my $updated = !defined($to_date) || $new_timestamp < str2time($to_date);

    if ($updated)
    {
        $to_date = format_date(time2isoz($new_timestamp));
    }

    return ($to_date, $updated);
}

sub format_date
{
    my $date = shift;
    $date =~ s/ /T/;
    $date =~ tr/-://d;
    return $date;
}

1;
