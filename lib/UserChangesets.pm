#!/usr/bin/perl

package UserChangesets;

use utf8;
use strict;
use warnings;
use File::Path qw(make_path);
use URI::Escape;
use HTTP::Date qw(str2time time2isoz);
use XML::Twig;
use OsmApi;
use OsmData;
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

sub print_date_range
{
    my ($from_timestamp, $to_timestamp) = @_;
    print "limiting results to time range ";
    print time2isoz($from_timestamp);
    print " .. ";
    print defined($to_timestamp) ? time2isoz($to_timestamp) : "now";
    print "\n";
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
            make_path($metadata_dirname);
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
        iterate_over_changesets_in_time_range($list_filename, $from_timestamp, $to_timestamp, sub {
            my ($id) = @_;
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
        make_path($changes_dirname);
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

sub download_previous
{
    my ($metadata_dirname, $changes_dirname, $previous_dirname, $store_dirname, $from_timestamp, $to_timestamp) = @_;

    my $changesets = read_metadata($metadata_dirname, $from_timestamp, $to_timestamp);
    my @ids_of_missing = grep { !-f "$previous_dirname/$_.osm" } keys %$changesets;
    if (scalar @ids_of_missing == 0)
    {
        print "all previous osm files already present\n";
        return;
    }
    my @ids = sort {$changesets->{$b}{created_at_timestamp} <=> $changesets->{$a}{created_at_timestamp}} @ids_of_missing;
    my $data = read_changes($changes_dirname, $store_dirname, @ids);
    write_previous($previous_dirname, $store_dirname, $data, @ids);
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
        iterate_over_changesets_in_time_range($list_filename, $from_timestamp, $to_timestamp, sub {
            my ($id) = @_;
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

sub read_metadata
{
    my ($metadata_dirname, $from_timestamp, $to_timestamp) = @_;

    my $changesets = {};
    foreach my $metadata_filename (list_osm_filenames($metadata_dirname))
    {
        print STDERR "reading metadata file $metadata_filename\n" if $OsmApi::prefs->{'debug'};

        my $twig = XML::Twig->new()->parsefile($metadata_filename);
        foreach my $changeset_element ($twig->root->children)
        {
            my $id = $changeset_element->att('id');
            next if $changesets->{$id};

            my $created_at = $changeset_element->att('created_at');
            my $closed_at = $changeset_element->att('closed_at');
            next if (str2time($closed_at) < $from_timestamp);
            next if (defined($to_timestamp) && str2time($created_at) >= $to_timestamp);

            my $comment_tag = $changeset_element->first_child('tag[@k="comment"]');
            my $comment = $comment_tag ? $comment_tag->att('v') : "";

            my $changeset = {
                created_at_timestamp => str2time($created_at),
                created_at => $created_at,
                closed_at => $closed_at,
                comment => $comment,
            };
            for my $key ('changes_count', 'min_lat', 'max_lat', 'min_lon', 'max_lon')
            {
                $changeset->{$key} = $changeset_element->att($key);
            }

            $changesets->{$id} = $changeset;
        }
    }
    return $changesets;
}

sub read_changes
{
    my ($changes_dirname, $store_dirname, @ids) = @_;

    my $data = OsmData::blank_data();
    OsmData::read_store_files("$store_dirname/changes", $data) if defined($store_dirname);
    my @ids_to_parse = ();
    my $bytes_to_parse = 0;
    foreach my $id (@ids)
    {
        my $changes_filename = "$changes_dirname/$id.osc";
        next unless -f $changes_filename;
        my $timestamp = (stat $changes_filename)[9];
        next if exists $data->{changesets}{$id} && $data->{changesets}{$id}[OsmData::DOWNLOAD_TIMESTAMP] <= $timestamp;
        $bytes_to_parse += (stat $changes_filename)[7];
        push @ids_to_parse, $id;
    }
    my $files_to_parse = scalar(@ids_to_parse);
    return $data if $files_to_parse == 0;
    
    print STDERR "going to parse $files_to_parse files, $bytes_to_parse bytes\n";
    my $new_data = OsmData::blank_data();
    my $have_changes_to_store = 0;
    my $files_parsed = 0;
    my $bytes_parsed = 0;
    my $quit = 0;
    local $SIG{INT} = sub {
        print STDERR "will interrupt after parsing and storing the current changes file\n";
        $quit = 1;
    };
    foreach my $id (@ids_to_parse)
    {
        last if $quit;
        my $changes_filename = "$changes_dirname/$id.osc";
        print STDERR "reading changes file $changes_filename ($files_parsed/$files_to_parse files) ($bytes_parsed/$bytes_to_parse bytes)\n" if $OsmApi::prefs->{'debug'};
        my $timestamp = (stat $changes_filename)[9];
        my $any_changes = OsmData::parse_changes_file($new_data, $id, $changes_filename, $timestamp);
        $have_changes_to_store ||= $any_changes;
        $bytes_parsed += (stat $changes_filename)[7];
        $files_parsed++;
    }
    if (defined($store_dirname) && $have_changes_to_store) {
        OsmData::write_store_file("$store_dirname/changes", $new_data);
    }
    die "interrupting" if $quit;
    OsmData::merge_data($data, $new_data);
    return $data;
}

sub merge_previous
{
    my ($store_dirname, $data) = @_;
    # unlike changes, previous versions are always parsed
    OsmData::read_store_files("$store_dirname/previous", $data) if defined($store_dirname);
}

sub write_previous
{
    my ($previous_dirname, $store_dirname, $data, @ids) = @_;

    OsmData::read_store_files("$store_dirname/previous", $data) if defined($store_dirname);
    my %data_to_write = ();
    foreach my $id (@ids)
    {
        my @changes = @{$data->{changesets}{$id}[OsmData::CHANGES]};
        my $eivs_in_changeset = [];
        foreach (@changes)
        {
            my ($e, $i, $v) = @$_;
            $eivs_in_changeset->[$e]{$i}{$v} = 1;
        }
        my @eivs_to_write = ();
        foreach (@changes)
        {
            my ($e, $i, $v) = @$_;
            next if $v <= 1;
            my $w = $v - 1;
            next if exists $eivs_in_changeset->[$e]{$i}{$w};
            push @eivs_to_write, [$e, $i, $w];
        }
        $data_to_write{$id} = \@eivs_to_write;
    }

    my @download_queues = ([], [], []);
    my @changeset_remaining_in_queue_counts = (scalar @ids) x 3;
    my %changeset_element_types_remaining = ();
    foreach my $id (@ids)
    {
        $changeset_element_types_remaining{$id} = 0b111;
        foreach (@{$data_to_write{$id}})
        {
            my ($e, $i, $v) = @$_;
            next if exists $data->{elements}[$e]{$i}{$v};
            push @{$download_queues[$e]}, [$i, $v];
        }
        push @{$download_queues[$_]}, [$id, 0] foreach (0..2);
    }

    make_path $previous_dirname;
    my $new_data = OsmData::blank_data();
    my $have_changes_to_store = 0;
    my $quit = 0;
    local $SIG{INT} = sub {
        print STDERR "will interrupt after downloading, parsing and storing the current batch of elements\n";
        $quit = 1;
    };
    while (1)
    {
        last if $quit;
        my $selected_queue_number = 0;
        my $selected_queue_remaining_count = $changeset_remaining_in_queue_counts[0];
        for my $e (1..2)
        {
            next if $selected_queue_remaining_count >= $changeset_remaining_in_queue_counts[$e];
            $selected_queue_number = $e;
            $selected_queue_remaining_count = $changeset_remaining_in_queue_counts[$e];
        }
        last if $selected_queue_remaining_count <= 0;
        my @changesets_ready_for_writing = ();
        my $selected_queue = $download_queues[$selected_queue_number];
        my $query = "";
        while (my $queue_item = shift @$selected_queue)
        {
            my ($i, $v) = @$queue_item;
            if ($v == 0)
            {
                $changeset_remaining_in_queue_counts[$selected_queue_number]--;
                $changeset_element_types_remaining{$i} &= ~(1 << $selected_queue_number);
                if ($changeset_element_types_remaining{$i} == 0)
                {
                    push @changesets_ready_for_writing, $i;
                }
                next;
            }
            $query .= "," if length($query) > 0;
            $query .= $i."v".$v;
            if (length($query) > 7500)
            {
                unshift @$selected_queue, $queue_item;
                last;
            }
        }
        if (length($query) > 0)
        {
            my $element = OsmData::element_string($selected_queue_number);
            $query = $element."s?".$element."s=".$query;
            my $resp = OsmApi::get("$query&show_redactions=true", "", 1);
            if (!$resp->is_success)
            {
                die "previous element versions cannot be retrieved: ".$resp->status_line."\n"; # TODO bisection fallback, esp. for redacted elements w/o moderator role
            }
            my $new_data_chunk = OsmData::blank_data();
            my $any_changes = OsmData::parse_elements($new_data_chunk, $resp->content());
            $have_changes_to_store ||= $any_changes;
            OsmData::merge_data($new_data, $new_data_chunk);
            OsmData::merge_data($data, $new_data_chunk);
        }
        for my $id (@changesets_ready_for_writing)
        {
            OsmData::write_osm_file("$previous_dirname/$id.osm", $data, @{$data_to_write{$id}});
        }
    }
    if (defined($store_dirname) && $have_changes_to_store)
    {
        OsmData::write_store_file("$store_dirname/previous", $new_data);
    }
}

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
        $handler->($id, $created_at, $closed_at);
    }
    close $list_fh;
}

sub iterate_over_changesets_in_time_range
{
    my ($list_source, $from_timestamp, $to_timestamp, $handler) = @_;
    iterate_over_changesets($list_source, sub {
        my ($id, $created_at, $closed_at) = @_;
        return if (str2time($closed_at) < $from_timestamp);
        return if (defined($to_timestamp) && str2time($created_at) >= $to_timestamp);
        $handler->($id);
    });
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

1;
