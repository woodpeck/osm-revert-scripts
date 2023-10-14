#!/usr/bin/perl

package UserChangesets;

use utf8;
use strict;
use warnings;
use POSIX qw(floor);
use Math::Trig qw(deg2rad);
use File::Path qw(make_path);
use URI::Escape;
use HTTP::Date qw(str2time time2isoz);
use HTML::Entities qw(encode_entities);
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
    my @ids = sort {$changesets->{$b}{created_at_timestamp} <=> $changesets->{$a}{created_at_timestamp}} keys %$changesets;
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

sub list
{
    my (
        $metadata_dirname, $changes_dirname, $store_dirname,
        $from_timestamp, $to_timestamp,
        $output_filename,
        $with_operation_counts, $with_element_counts, $with_operation_x_element_counts,
        $target_delete_tag
    ) = @_;

    my $changesets = read_metadata($metadata_dirname, $from_timestamp, $to_timestamp);
    my @ids = sort {$changesets->{$b}{created_at_timestamp} <=> $changesets->{$a}{created_at_timestamp}} keys %$changesets;
    my $need_changes = $with_operation_counts || $with_element_counts || $with_operation_x_element_counts || defined($target_delete_tag);
    my $data;
    if ($need_changes)
    {
        $data = read_changes($changes_dirname, $store_dirname, @ids);
    }

    my @changeset_items = ();
    foreach my $id (@ids)
    {
        my $changeset = $changesets->{$id};
        my $time = time2isoz($changeset->{created_at_timestamp});
        chop $time;

        my %change_counts = ();
        my ($target_exact_count, $target_upper_count);

        if ($need_changes && exists $data->{changesets}{$id})
        {
            foreach my $o ("a", "c", "m", "d")
            {
                foreach my $e ("a", "n", "w", "r")
                {
                    $change_counts{"${o}${e}"} = 0;
                }
            }
            my @changes = @{$data->{changesets}{$id}[OsmData::CHANGES]};
            $target_upper_count = $changeset->{changes_count} - scalar(@changes);
            foreach my $change (@changes)
            {
                my ($t, $i, $v) = @$change;
                my $element = $data->{elements}[$t]{$i}{$v};
                my $o = operation_letter_from_version_and_element($v, $element);
                my $e = type_letter_from_type($t);
                $change_counts{"aa"}++;
                $change_counts{"${o}a"}++;
                $change_counts{"a${e}"}++;
                $change_counts{"${o}${e}"}++;
                if (defined($target_delete_tag))
                {
                    if (
                        $v > 1 &&
                        $element->[OsmData::VISIBLE] &&
                        !exists $element->[OsmData::TAGS]{$target_delete_tag}
                    ) {
                        $target_upper_count++;
                    }
                }
            }
        }
        elsif ($changeset->{changes_count} == 0)
        {
            $target_upper_count = 0;
        }

        if (defined($target_upper_count))
        {
            $target_exact_count = 0 if ($target_upper_count == 0);
        }

        my $item =
            "<li class=changeset>" .
            "<a href='".html_escape(OsmApi::weburl("changeset/$id"))."' data-number=id>".html_escape($id)."</a>" .
            " <time datetime='".html_escape($changeset->{created_at})."'>".html_escape($time)."</time>";
        if ($need_changes)
        {
            $item .= " <span class='changes changes-total'>" . get_changes_widget_parts(
                ["📝", "total number of changes", "changes-total", $changeset->{changes_count}],
                ["⬇", "number of downloaded changes", "changes-downloaded", $change_counts{"aa"} // 0, "oa ea"]
            ) . "</span>";
        }
        else
        {
            $item .= " <span class='changes changes-total'>" . get_changes_widget_parts(
                ["📝", "total number of changes", "changes-total", $changeset->{changes_count}]
            ) . "</span>";
        }
        if ($with_operation_counts)
        {
            my @parts = map { my $o = substr($_, 0, 1);
                ["", "number of $_ changes", "changes-$_", $change_counts{"${o}a"}, "o${o} ea"]
            } ("create", "modify", "delete");
            $item .= " <span class='changes changes-operation'>" . get_changes_widget_parts(
                ["📝", "number of changes by operation"], @parts
            ) . "</span>";
        }
        if ($with_element_counts)
        {
            my @parts = map { my $e = substr($_, 0, 1);
                ["$e:", "number of $_ changes", "changes-$_", $change_counts{"a${e}"}, "oa e${e}"]
            } ("node", "way", "relation");
            $item .= " <span class='changes changes-element'>" . get_changes_widget_parts(
                ["📝", "number of changes by element type"], @parts
            ) . "</span>";
        }
        if ($with_operation_x_element_counts)
        {
            my @parts = (["📝", "number of changes by operation and element type"]);
            foreach my $element ("node", "way", "relation")
            {
                my $e = substr($element, 0, 1);
                push @parts, ["$e:", "number of $element changes"];
                foreach my $operation ("create", "modify", "delete")
                {
                    my $o = substr($operation, 0, 1);
                    push @parts, ["", "number of $operation $element changes", "changes-$operation-$element", $change_counts{"${o}${e}"}, "o${o} e${e}"];
                }
            }
            $item .= " <span class='changes changes-operation-x-element'>" . get_changes_widget_parts(@parts) . "</span>";
        }
        if (defined($target_delete_tag))
        {
            $item .= " <span class='changes changes-target'>" . get_changes_widget_parts(
                ["🎯", "number of target changes", "changes-target-exact", $target_exact_count, "exact"],
                ["≤", "upper bound of number of target changes", "changes-target-upper", $target_upper_count, "upper"],
            ) . "</span>";
        }
        $item .=
            " " . get_area_widget(
                $changeset->{min_lat}, $changeset->{max_lat},
                $changeset->{min_lon}, $changeset->{max_lon}
            ) .
            " <span class=comment>".html_escape($changeset->{comment})."</span>" .
            "</li>\n";
        push @changeset_items, $item;
    }

    my ($fh, $fh_template, $fh_asset);
    open($fh, '>:utf8', $output_filename) or die "can't open html list file '$output_filename' for writing";
    open_asset(\$fh_template, "list.html");
    while (<$fh_template>)
    {
        if (!/<\!-- \{embed (.*)\} -->/)
        {
            print $fh $_;
        }
        elsif ($1 eq "style")
        {
            print $fh "<style>\n";
            open_asset(\$fh_asset, "list.css");
            print $fh $_ while <$fh_asset>;
            close $fh_asset;
            print $fh "</style>\n";
        }
        elsif ($1 eq "items")
        {
            print $fh $_ for @changeset_items;
        }
        elsif ($1 eq "script")
        {
            print $fh
                "<script>\n" .
                "const weburl = '".OsmApi::weburl()."';\n\n";
            open_asset(\$fh_asset, "list.js");
            print $fh $_ while <$fh_asset>;
            close $fh_asset;
            print $fh
                "</script>";
        }
    }
    close $fh_template;
    close $fh;
}

# -----------------------------------------------------------------------------

sub get_changes_widget_parts
{
    return join "", (map {
        my ($text, $title, $number_group, $number, $extra_classes) = @$_;
        my @classes = ("part");
        push @classes, $extra_classes if defined($extra_classes);
        push @classes, "empty" if !defined($number) || $number == 0;
        my $class = scalar(@classes) == 1 ? $classes[0] : "'".join(" ", @classes)."'";
        "<span class=$class title='".html_escape($title)."'>".html_escape($text).(
            defined($number_group)
            ? "<span data-number=$number_group>".html_escape($number // "?")."</span>"
            : ""
        )."</span>";
    } @_);
}

sub get_area_widget
{
    my ($min_lat, $max_lat, $min_lon, $max_lon) = @_;
    my ($area, $log_area);

    if (
        defined($min_lat) && defined($max_lat) &&
        defined($min_lon) && defined($max_lon)
    )
    {
        $area = (sin(deg2rad($max_lat)) - sin(deg2rad($min_lat))) * ($max_lon - $min_lon) / 720; # 1 = entire Earth surface
        if ($area > 0) {
            $log_area = log($area) / log(10);
        }
    }

    if (!defined($area))
    {
        return " <span class='area empty' title='no bounding box'>✕</span>";
    }
    elsif ($area == 0)
    {
        return " <span class='area zero' title='zero-sized bounding box'>·</span>";
    }
    else
    {
        return " <span class=area title='-log10(bbox area); ".html_escape(earth_area_with_units($area))."' data-log-value='".html_escape($log_area)."'>".html_escape(sprintf "%.2f", $log_area)."</span>";
    }
}

sub operation_letter_from_version_and_element
{
    my ($v, $element) = @_;
    if ($v == 1)
    {
        return 'c';
    }
    elsif ($element->[OsmData::VISIBLE])
    {
        return 'm';
    }
    else
    {
        return 'd';
    }
}

sub type_letter_from_type
{
    my ($t) = @_;
    return ('n', 'w', 'r')[$t];
}

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

    my $data = OsmData::read_store_files($store_dirname, "changes");
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
        print STDERR "will interrupt after parsing and storing the current changes file";
        $quit = 1;
    };
    foreach my $id (@ids_to_parse)
    {
        last if $quit;
        my $changes_filename = "$changes_dirname/$id.osc";
        print STDERR "reading changes file $changes_filename ($files_parsed/$files_to_parse files) ($bytes_parsed/$bytes_to_parse bytes)\n" if $OsmApi::prefs->{'debug'};
        my $timestamp = (stat $changes_filename)[9];
        OsmData::parse_changes_file($new_data, $id, $changes_filename, $timestamp);
        $have_changes_to_store = 1;
        $bytes_parsed += (stat $changes_filename)[7];
        $files_parsed++;
    }
    if (defined($store_dirname) && $have_changes_to_store) {
        OsmData::write_store_file($store_dirname, "changes", $new_data);
    }
    die "interrupting" if $quit;
    OsmData::merge_data($data, $new_data);
    return $data;
}

sub write_previous
{
    my ($previous_dirname, $store_dirname, $data, @ids) = @_;

    # TODO read previous data
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

    my $new_data = OsmData::blank_data();
    while (1)
    {
        # TODO interrupt w/ partial write
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
        my $element = OsmData::element_string($selected_queue_number);
        $query = $element."s?".$element."s=".$query;
        my $resp = OsmApi::get("$query&show_redactions=true", "", 1);
        if (!$resp->is_success)
        {
            die "previous element versions cannot be retrieved: ".$resp->status_line."\n"; # TODO bisection fallback, esp. for redacted elements w/o moderator role
        }
        OsmData::parse_elements($new_data, $resp->content());
        # TODO merge chunk into both to-write data and full data
        print "TODO write changesets: " . join(",", @changesets_ready_for_writing) . "\n";
    }
    if (defined($store_dirname))
    {
        OsmData::write_store_file($store_dirname, "previous", $new_data);
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

sub html_escape
{
    my $s = shift;
    return encode_entities($s, '<>&"');
}

sub open_asset
{
    my ($fh_ref, $filename) = @_;
    open($$fh_ref, '<:utf8', $FindBin::Bin."/assets/".$filename) or die $!;
}

sub earth_area_with_units
{
    my $area = shift;
    my $km2_area = 510072000 * $area;
    if (log($km2_area) / log(10) >= -1)
    {
        return format_to_significant_figures($km2_area, 3) . " km²";
    }
    else
    {
        return format_to_significant_figures($km2_area * 1000000, 3) . " m²";
    }
}

sub format_to_significant_figures
{
    my ($v, $n) = @_;
    my $e = floor(log($v) / log(10));
    my $p = -($n - $e - 1);
    if ($p<0 && $p>-$n) {
        return sprintf "%.*g", $n, $v;
    } else {
        my $s = "";
        $s .= "0." . ("0" x (-1 - $e)) if $e < 0;
        $s .= int($v * 0.1 ** $p);
        $s .= "0" x $p if $p >= 0;
        return $s;
    }
}

1;
