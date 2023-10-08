#!/usr/bin/perl

package UserChangesets;

use utf8;
use strict;
use warnings;
use POSIX qw(floor);
use Math::Trig qw(deg2rad);
use URI::Escape;
use HTTP::Date qw(str2time time2isoz);
use HTML::Entities qw(encode_entities);
use OsmApi;
use Changeset;

our $max_int_log_area = 11;

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

    my (
        $metadata_dirname, $changes_dirname, $from_timestamp, $to_timestamp,
        $output_filename, $with_operation_counts, $with_element_counts
    ) = @_;
    my %changeset_items = ();
    my %changeset_dates = ();
    my $max_id_length = 1;
    my %max_change_counts_length = ();
    foreach my $o ("a", "c", "m", "d")
    {
        foreach my $e ("a", "c", "m", "d")
        {
            $max_change_counts_length{"${o}${e}"} = 1;
        }
    }

    foreach my $metadata_filename (list_osm_filenames($metadata_dirname))
    {
        print STDERR "reading changeset metadata file $metadata_filename\n" if $OsmApi::prefs->{'debug'};

        my $twig = XML::Twig->new()->parsefile($metadata_filename);
        foreach my $changeset ($twig->root->children)
        {
            my $id = $changeset->att('id');
            next if $changeset_items{$id};

            my $created_at = $changeset->att('created_at');
            my $closed_at = $changeset->att('closed_at');
            next if (str2time($closed_at) < $from_timestamp);
            next if (defined($to_timestamp) && str2time($created_at) >= $to_timestamp);

            update_max_length(\$max_id_length, $id);

            my $timestamp = str2time($created_at);
            $changeset_dates{$id} = $timestamp;
            my $time = time2isoz($timestamp);
            chop $time;

            my %change_counts = ();
            $change_counts{"aa"} = $changeset->att('changes_count');
            update_max_length(\$max_change_counts_length{"aa"}, $change_counts{"aa"});

            my $changes_filename = "$changes_dirname/$id.osc";
            if ($with_operation_counts && -e $changes_filename)
            {
                print STDERR "reading changeset changes file $changes_filename\n" if $OsmApi::prefs->{'debug'};
                foreach my $o ("c", "m", "d")
                {
                    $change_counts{"${o}a"} = 0;
                    if ($with_element_counts)
                    {
                        foreach my $e ("n", "w", "r")
                        {
                            $change_counts{"${o}${e}"} = 0
                        }
                    }
                }
                if ($with_element_counts)
                {
                    my $in_o;
                    XML::Twig->new(
                        start_tag_handlers => {
                            create => sub { $in_o = "c" },
                            modify => sub { $in_o = "m" },
                            delete => sub { $in_o = "d" },
                        },
                        twig_handlers => {
                            node     => sub { $change_counts{"${in_o}n"}++ if defined($in_o) },
                            way      => sub { $change_counts{"${in_o}w"}++ if defined($in_o) },
                            relation => sub { $change_counts{"${in_o}r"}++ if defined($in_o) },
                            create => sub { $in_o = undef; $change_counts{"ca"}++ },
                            modify => sub { $in_o = undef; $change_counts{"ma"}++ },
                            delete => sub { $in_o = undef; $change_counts{"da"}++ },
                        },
                    )->parsefile($changes_filename);
                }
                else
                {
                    XML::Twig->new(
                        twig_handlers => {
                            create => sub { $change_counts{"ca"}++ },
                            modify => sub { $change_counts{"ma"}++ },
                            delete => sub { $change_counts{"da"}++ },
                        }
                    )->parsefile($changes_filename);
                }
                foreach my $o ("c", "m", "d")
                {
                    update_max_length(\$max_change_counts_length{"${o}a"}, $change_counts{"${o}a"});
                    if ($with_element_counts)
                    {
                        foreach my $e ("n", "w", "r")
                        {
                            update_max_length(\$max_change_counts_length{"${o}${e}"}, $change_counts{"${o}${e}"});
                        }
                    }
                }
            }

            my $comment_tag = $changeset->first_child('tag[@k="comment"]');
            my $comment = $comment_tag ? $comment_tag->att('v') : "";

            my $item =
                "<li class=changeset>" .
                "<a href='".html_escape(OsmApi::weburl("changeset/$id"))."'>".html_escape($id)."</a>" .
                " <time datetime='".html_escape($created_at)."'>".html_escape($time)."</time>" .
                " " . get_changes_widget(\%change_counts, $with_operation_counts, $with_element_counts) .
                " " . get_area_widget(
                    $changeset->att('min_lat'), $changeset->att('max_lat'),
                    $changeset->att('min_lon'), $changeset->att('max_lon')
                ) .
                " <span class=comment>".html_escape($comment)."</span>" .
                "</li>\n";
            $changeset_items{$id} = $item;
        }
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
            print $fh
                "<style>\n" .
                ":root {\n" .
                "    --changesets-count-width: ".length(keys %changeset_items)."ch;\n" .
                "    --id-width: ${max_id_length}ch;\n" .
                "}\n\n";
            open_asset(\$fh_asset, "list.css");
            print $fh $_ while <$fh_asset>;
            close $fh_asset;
            for (0 .. $max_int_log_area)
            {
                my $width = sprintf "%.2f", 6.5 - $_ / 2;
                print $fh "#items li.changeset .area[data-log-size='$_']:before { width: ${width}ch; }\n";
            }
            print $fh "#items li.changeset .changes .number.oa.ea { min-width: ".$max_change_counts_length{"aa"}."ch; }\n";
            if ($with_operation_counts)
            {
                foreach my $o ("c", "m", "d")
                {
                    print $fh "#items li.changeset .changes .number.o${o}.ea { min-width: ".$max_change_counts_length{"${o}a"}."ch; }\n";
                    if ($with_element_counts)
                    {
                        foreach my $e ("n", "w", "r")
                        {
                            print $fh "#items li.changeset .changes .number.o${o}.e${e} { min-width: ".$max_change_counts_length{"${o}${e}"}."ch; }\n";
                        }
                    }
                }
            }
            print $fh
                "</style>\n";
        }
        elsif ($1 eq "items")
        {
            foreach my $id (sort {$changeset_dates{$b} <=> $changeset_dates{$a}} keys %changeset_dates)
            {
                print $fh $changeset_items{$id};
            }
        }
        elsif ($1 eq "script")
        {
            print $fh
                "<script>\n" .
                "const weburl = '".OsmApi::weburl()."';\n" .
                "const maxIdLength = $max_id_length;\n\n";
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

sub get_changes_widget
{
    my ($counts, $with_operation_counts, $with_element_counts) = @_; # with two-letter keys: one of (a c m d) + one of (a n w r)
    my $sum_count;
    my $widget = "";
    $widget .= "<span class=changes title='number of changes'>📝";
    $widget .= "<span class='number oa ea'>".html_escape($counts->{'aa'})."</span>";

    if ($with_operation_counts)
    {
        if (defined($counts->{"ca"}) && defined($counts->{"ma"}) && defined($counts->{"da"}))
        {
            $sum_count = $counts->{"ca"} + $counts->{"ma"} + $counts->{"da"};
        }
        $widget .= defined($sum_count) && $counts->{"aa"} == $sum_count ? "=" : "≠";
        my $i = 0;
        foreach my $operation ("create", "modify", "delete")
        {
            $widget .= "+" if $i++;
            my $o = substr($operation, 0, 1);
            $widget .= "<span class='number o$o ea' title='number of $operation changes'>".html_escape($counts->{"${o}a"} // "?")."</span>";
            if ($with_element_counts)
            {
                $widget .= "(";
                my $j = 0;
                foreach my $element ("node", "way", "relation")
                {
                    $widget .= "+" if $j++;
                    my $e = substr($element, 0, 1);
                    $widget .= "<span class='number o$o e$e' title='number of $operation $element changes'>".html_escape($counts->{"${o}${e}"} // "?")."</span>$e";
                }
                $widget .= ")";
            }
        }
    }
    $widget .= "</span>";
    return $widget;
}

sub get_area_widget
{
    my ($min_lat, $max_lat, $min_lon, $max_lon) = @_;
    my ($area, $log_area, $int_log_area);

    if (
        defined($min_lat) && defined($max_lat) &&
        defined($min_lon) && defined($max_lon)
    )
    {
        $area = (sin(deg2rad($max_lat)) - sin(deg2rad($min_lat))) * ($max_lon - $min_lon) / 720; # 1 = entire Earth surface
        if ($area > 0) {
            $log_area = sprintf "%.2f", log($area) / log(10);
            $int_log_area = -int($log_area);
            $int_log_area = 0 if $int_log_area < 0;
            $int_log_area = $max_int_log_area if $int_log_area > $max_int_log_area;
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
        return " <span class=area title='-log10(bbox area); ".html_escape(earth_area_with_units($area))."' data-log-size=$int_log_area>".html_escape($log_area)."</span>";
    }
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

sub update_max_length
{
    my ($max_length_ref, $value) = @_;
    $$max_length_ref = length($value) if length($value) > $$max_length_ref;
}

1;
