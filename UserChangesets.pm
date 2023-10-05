#!/usr/bin/perl

package UserChangesets;

use utf8;
use strict;
use warnings;
use URI::Escape;
use HTTP::Date qw(str2time time2isoz);
use HTML::Entities qw(encode_entities);
use OsmApi;
use Changeset;

# -----------------------------------------------------------------------------
# Converts date string from script arguments to timestamp
# Returns undefined if date format is not recognized

sub parse_date
{
    my ($date) = @_;
    return undef unless defined($date);
    $date = "$1-$2-01" if $date =~ /^(\d\d\d\d)-(\d\d)$/;
    $date = "$1-01-01" if $date =~ /^(\d\d\d\d)$/;
    return str2time($date, "GMT");
}

# -----------------------------------------------------------------------------
# Downloads given user's changeset metadata (open/close dates, bboxes, tags, ...)
# Parameters: metadata directory for output, user argument, from timestamp, to timestamp
# user argument is either display_name=... or user=... with urlencoded display name or id

sub download_metadata
{
    my ($metadata_dirname, $user_arg, $from_timestamp, $to_timestamp) = @_;
    my $updated_to_timestamp = $to_timestamp;
    my %visited_changesets = ();
    my $download_more = 1;

    # existing metadata check phase

    foreach my $list_filename (list_osm_filenames($metadata_dirname))
    {
        my $bottom_created_at;
        iterate_over_changesets($list_filename, sub {
            my ($id, $created_at, $closed_at) = @_;
            $bottom_created_at = $created_at;
            if (!$visited_changesets{$id}) {
                $visited_changesets{$id} = 1;
            }
        });
        ($updated_to_timestamp, $download_more) = update_to_timestamp($updated_to_timestamp, $bottom_created_at) if defined($bottom_created_at);
    }

    # new metadata download phase

    while ($download_more)
    {
        my $time_arg = "";
        if (defined($updated_to_timestamp))
        {
            $time_arg = "time=" . make_http_date_from_timestamp($from_timestamp) . "," . make_http_date_from_timestamp($updated_to_timestamp);
            print "requesting changeset metadata down from " . time2isoz($updated_to_timestamp) . "\n";
        }
        else
        {
            $time_arg = "time=" . make_http_date_from_timestamp($from_timestamp);
            print "requesting changeset metadata down from current moment\n";
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
            my $list_filename = "$metadata_dirname/" . make_filename_from_date_attr_value($top_created_at);
            open(my $list_fh, '>', $list_filename) or die "can't open changeset list file '$list_filename' for writing";
            print $list_fh $list;
            close $list_fh;
        }

        last if $new_changesets_count == 0;

        ($updated_to_timestamp) = update_to_timestamp($updated_to_timestamp, $bottom_created_at);
    }
}

# -----------------------------------------------------------------------------
# Downloads changeset changes (elements) matching provided metadata and date rande
# Parameters: metadata directory to be scanned, changes directory for output, from timestamp, to timestamp

sub download_changes
{
    my ($metadata_dirname, $changes_dirname, $from_timestamp, $to_timestamp) = @_;
    my %changesets_in_range = ();
    my %changesets_downloaded = ();
    my %changesets_to_download = ();
    my @changesets_queue;

    foreach my $list_filename (list_osm_filenames($metadata_dirname))
    {
        iterate_over_changesets($list_filename, sub {
            my ($id, $created_at, $closed_at) = @_;
            return if (str2time($closed_at) < $from_timestamp);
            return if (defined($to_timestamp) && str2time($created_at) >= $to_timestamp);
            $changesets_in_range{$id} = 1;
            my $changes_filename = "$changes_dirname/$id.osc";
            if (-f $changes_filename)
            {
                $changesets_downloaded{$id} = 1;
            }
            else
            {
                push @changesets_queue, $id unless $changesets_to_download{$id};
                $changesets_to_download{$id} = 1;
            }
        });
    }

    if (@changesets_queue > 0)
    {
        print((0 + @changesets_queue) . " changesets left to download\n");
    }
    else
    {
        print("all " . (keys %changesets_in_range) . " changesets already downloaded\n");
    }

    foreach my $id (@changesets_queue)
    {
        print("downloading $id.osc (" . (1 + keys %changesets_downloaded) . "/" . (keys %changesets_in_range) . ")\n");
        my $changes_filename = "$changes_dirname/$id.osc";
        my $osc = Changeset::download($id) or die "failed to download changeset $id";
        open(my $fh, '>', $changes_filename) or die "can't open changes file '$changes_filename' for writing";
        print $fh $osc;
        close $fh;
        delete $changesets_to_download{$id};
        $changesets_downloaded{$id} = 1;
    }
}

# -----------------------------------------------------------------------------
# Count downloaded changesets inside given date range
# Parameters: metadata directory, changes directory, from timestamp, to timestamp

sub count
{
    my ($metadata_dirname, $changes_dirname, $from_timestamp, $to_timestamp) = @_;
    my %visited_changesets = ();
    my $metadata_count = 0;
    my $changes_count = 0;

    foreach my $list_filename (list_osm_filenames($metadata_dirname))
    {
        iterate_over_changesets($list_filename, sub {
            my ($id, $created_at, $closed_at) = @_;
            return if (str2time($closed_at) < $from_timestamp);
            return if (defined($to_timestamp) && str2time($created_at) >= $to_timestamp);
            return if $visited_changesets{$id};
            $visited_changesets{$id} = 1;
            $metadata_count++;
            if (defined($changes_dirname)) {
                my $changes_filename = "$changes_dirname/$id.osc";
                $changes_count++ if -e $changes_filename;
            }
        });
    }

    print "downloaded $metadata_count changeset metadata records\n";
    print "downloaded $changes_count changeset change files\n" if defined($changes_dirname);
}

# -----------------------------------------------------------------------------

sub list
{
    use XML::Twig;

    my ($html_filename, $metadata_dirname, $from_timestamp, $to_timestamp) = @_;
    my %visited_changesets = ();
    my $fh;
    my $html_style = read_asset("list.css");
    my $html_script = read_asset("list.js");
    my $weburl = OsmApi::weburl();

    open($fh, '>:utf8', $html_filename) or die "can't open html list file '$html_filename' for writing";
    print $fh <<HTML;
<!DOCTYPE html>
<html lang=en>
<head>
<meta charset=utf-8>
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>list of changesets</title>
<meta name=color-scheme content="light dark">
<style>
${html_style}</style>
</head>
<body>
<main>
<ul id=items>
HTML

    foreach my $list_filename (list_osm_filenames($metadata_dirname))
    {
        my $twig = XML::Twig->new()->parsefile($list_filename);
        foreach my $changeset ($twig->root->children)
        {
            my $id = $changeset->att('id');
            next if $visited_changesets{$id};
            $visited_changesets{$id} = 1;

            my $created_at = $changeset->att('created_at');
            my $closed_at = $changeset->att('closed_at');
            next if (str2time($closed_at) < $from_timestamp);
            next if (defined($to_timestamp) && str2time($created_at) >= $to_timestamp);

            my $time = time2isoz(str2time($created_at));
            chop $time;
            my $changes = $changeset->att('changes_count');
            my $comment_tag = $changeset->first_child('tag[@k="comment"]');
            my $comment = $comment_tag ? $comment_tag->att('v') : "";

            print $fh "<li class=changeset>";
            print $fh "<a href='".html_escape(OsmApi::weburl("changeset/$id"))."'>".html_escape($id)."</a>";
            print $fh " <time datetime='".html_escape($created_at)."'>".html_escape($time)."</time>";
            print $fh " <span class=changes title='number of changes'>📝<span class=count>".html_escape($changes)."</span></span>";
            print $fh " <span class=comment>".html_escape($comment)."</span>";
            print $fh "</li>\n";
        }
    }

    print $fh <<HTML;
</ul>
</main>
<script>
const weburl = "$weburl";

${html_script}</script>
</body>
</html>
HTML
    close $fh;
}

# -----------------------------------------------------------------------------

sub list_osm_filenames
{
	my $dirname = shift;
	return reverse glob qq{"$dirname/*.osm"};
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
        $handler -> ($id, $created_at, $closed_at);
    }
    close $list_fh;
}

sub update_to_timestamp
{
    my ($to_timestamp, $bottom_created_at) = @_;
    my $new_timestamp = str2time($bottom_created_at) + 1;
    my $updated = !defined($to_timestamp) || $new_timestamp < $to_timestamp;

    if ($updated)
    {
        $to_timestamp = $new_timestamp;
    }

    return ($to_timestamp, $updated);
}

sub make_http_date_from_timestamp
{
    my $timestamp = shift;
    my $date = time2isoz($timestamp);
    return uri_escape(make_compact_date($date));
}

sub make_filename_from_date_attr_value
{
    my $date_attr_value = shift;
    my $timestamp = str2time($date_attr_value);
    die "invalid date format in xml date attribute ($date_attr_value)" unless defined($timestamp);
    return make_compact_date(time2isoz($timestamp)) . ".osm";
}

sub make_compact_date
{
    my $date = shift;
    $date =~ s/ /T/;
    $date =~ tr/-://d;
    return $date;
}

sub html_escape
{
    my $s = shift;
    return encode_entities($s, '<>&"');
}

sub read_asset
{
    my $filename = shift;
    open(my $fh, '<:utf8', $FindBin::Bin."/assets/".$filename) or die $!;
    my $asset = do { local $/; <$fh> };
    close $fh;
    return $asset;
}

1;
