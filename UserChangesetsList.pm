#!/usr/bin/perl

package UserChangesetsList;

use utf8;
use strict;
use warnings;
use POSIX qw(floor);
use Math::Trig qw(deg2rad);
use HTTP::Date qw(str2time time2isoz);
use HTML::Entities qw(encode_entities);
use OsmData;
use UserChangesets;

sub list
{
    my (
        $metadata_dirname, $changes_dirname, $store_dirname,
        $from_timestamp, $to_timestamp,
        $output_filename,
        $show_options, $target_delete_tag
    ) = @_;

    my $changesets = UserChangesets::read_metadata($metadata_dirname, $from_timestamp, $to_timestamp);
    my @ids = sort {$changesets->{$b}{created_at_timestamp} <=> $changesets->{$a}{created_at_timestamp}} keys %$changesets;
    my $need_changes = $show_options->{operation_counts} || $show_options->{element_counts} || $show_options->{operation_x_element_counts} || defined($target_delete_tag);
    my $data;
    if ($need_changes)
    {
        $data = UserChangesets::read_changes($changes_dirname, $store_dirname, @ids);
    }

    my @changeset_items = ();
    foreach my $id (@ids)
    {
        my $changeset = $changesets->{$id};
        my $time = time2isoz($changeset->{created_at_timestamp});
        chop $time;

        my %change_counts = ();
        my $target_lower_count = 0;
        my $target_upper_count = $changeset->{changes_count};
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
                    )
                    {
                        my $previous_element = $data->{elements}[$t]{$i}{$v - 1};
                        if (defined($previous_element))
                        {
                            if (
                                $previous_element->[OsmData::VISIBLE] &&
                                exists $previous_element->[OsmData::TAGS]{$target_delete_tag}
                            )
                            {
                                $target_lower_count++;
                            }
                            else
                            {
                                $target_upper_count--;
                            }
                        }
                    }
                    else
                    {
                        $target_upper_count--;
                    }
                }
            }
        }
        elsif ($changeset->{changes_count} == 0)
        {
            $target_upper_count = 0;
        }

        my $target_exact_count;
        if (defined($target_upper_count))
        {
            $target_exact_count = $target_upper_count if ($target_upper_count == $target_lower_count);
        }

        my $item =
            "<li class=changeset>" .
            "<a href='".html_escape(OsmApi::weburl("changeset/$id"))."' data-number=id>".html_escape($id)."</a>" .
            " <time datetime='".html_escape($changeset->{created_at})."'>".html_escape($time);
        if ($show_options->{close_time})
        {
            $item .= " .. ".html_escape($changeset->{closed_at});
        }
        $item .=
            "</time>";
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
        if ($show_options->{operation_counts})
        {
            my @parts = map { my $o = substr($_, 0, 1);
                ["", "number of $_ changes", "changes-$_", $change_counts{"${o}a"}, "o${o} ea"]
            } ("create", "modify", "delete");
            $item .= " <span class='changes changes-operation'>" . get_changes_widget_parts(
                ["📝", "number of changes by operation"], @parts
            ) . "</span>";
        }
        if ($show_options->{element_counts})
        {
            my @parts = map { my $e = substr($_, 0, 1);
                ["$e:", "number of $_ changes", "changes-$_", $change_counts{"a${e}"}, "oa e${e}"]
            } ("node", "way", "relation");
            $item .= " <span class='changes changes-element'>" . get_changes_widget_parts(
                ["📝", "number of changes by element type"], @parts
            ) . "</span>";
        }
        if ($show_options->{operation_x_element_counts})
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

sub open_asset
{
    my ($fh_ref, $filename) = @_;
    open($$fh_ref, '<:utf8', $FindBin::Bin."/assets/".$filename) or die $!;
}

sub html_escape
{
    my $s = shift;
    return encode_entities($s, '<>&"');
}

1;
