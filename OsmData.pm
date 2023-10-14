#!/usr/bin/perl

package OsmData;

use Math::Round qw(round);
use HTTP::Date qw(str2time);
use HTML::Entities qw(encode_entities);
use File::Path qw(make_path);
use Storable;
use XML::Twig;
use OsmApi;

use constant {
    NODE => 0,
    WAY => 1,
    RELATION => 2,
};

# changeset
use constant {
    CHANGES => 0,
    DOWNLOAD_TIMESTAMP => 1,
};

# element
use constant {
    CHANGESET => 0,
    TIMESTAMP => 1,
    UID => 2,
    VISIBLE => 3,
    TAGS => 4,
    LAT => 5, LON => 6,
    NDS => 5,
    MEMBERS => 5,
};

# change
use constant {
    TYPE => 0,
    ID => 1,
    VERSION => 2,
};

use constant SCALE => 10000000;

sub element_type
{
    my ($type_string) = @_;
    return NODE if $type_string eq "node";
    return WAY if $type_string eq "way";
    return RELATION if $type_string eq "relation";
    die "unknown element type $type_string";
}
sub element_string
{
    my ($type) = @_;
    return ("node", "way", "relation")[$type];
}

sub blank_data
{
    return {
        changesets => {},
        elements => [{}, {}, {}],
    };
}

sub merge_data
{
    my ($data1, $data2) = @_;
    foreach my $id (keys %{$data2->{changesets}})
    {
        $data1->{changesets}{$id} = $data2->{changesets}{$id};
    }
    my $elements1 = $data1->{elements};
    my $elements2 = $data2->{elements};
    foreach my $type (NODE, WAY, RELATION)
    {
        foreach my $id (keys %{$elements2->[$type]})
        {
            if (exists $elements1->[$type]{$id})
            {
                foreach my $version (keys %{$elements2->[$type]{$id}})
                {
                    $elements1->[$type]{$id}{$version} = $elements2->[$type]{$id}{$version};
                }
            }
            else
            {
                $elements1->[$type]{$id} = $elements2->[$type]{$id};
            }
        }
    }
}

sub print_data_items
{
    my ($data) = @_;
    foreach my $id (keys %{$data->{changesets}})
    {
        print "changeset/$id\n";
    }
    my $elements = $data->{elements};
    foreach my $type (NODE, WAY, RELATION)
    {
        my $element = element_string($type);
        foreach my $id (keys %{$elements->[$type]})
        {
            print "$element/${id}v" . join(",", keys %{$elements->[$type]{$id}}) . "\n";
        }
    }
}

sub parse_changes_file
{
    my ($data, $id, $filename, $timestamp) = @_;

    open my $fh, '<:utf8', $filename;
    my @changes = parse_elements($data, $fh);
    close $fn;

    $data->{changesets}{$id} = [
        \@changes,
        $timestamp,
    ];

    return !!@changes;
}

sub parse_elements_string
{
    my ($data, $xml) = @_;

    my @elements = parse_elements($data, $xml);

    return !!@elements;
}

sub parse_elements
{
    my ($data, $xml) = @_;
    my @elements = ();

    XML::Twig->new(
        twig_handlers => {
            node => sub {
                my($twig, $element_twig) = @_;
                my ($type, $id, $version, @edata) = parse_common_element_data($element_twig);
                push @elements, [$type, $id, $version];
                if ($edata[VISIBLE])
                {
                    push @edata,
                        round(SCALE * $element_twig->att('lat')),
                        round(SCALE * $element_twig->att('lon'));
                }
                $data->{elements}[$type]{$id}{$version} = \@edata;
            },
            way => sub {
                my($twig, $element_twig) = @_;
                my ($type, $id, $version, @edata) = parse_common_element_data($element_twig);
                push @elements, [$type, $id, $version];
                $data->{elements}[$type]{$id}{$version} = [
                    @edata,
                    [ map { int $_->att('ref') } $element_twig->children('nd') ]
                ];
            },
            relation => sub {
                my($twig, $element_twig) = @_;
                my ($type, $id, $version, @edata) = parse_common_element_data($element_twig);
                push @elements, [$type, $id, $version];
                $data->{elements}[$type]{$id}{$version} = [
                    @edata,
                    [ map { [
                        element_type($_->att('type')),
                        int $_->att('ref'),
                        $_->att('role'),
                    ] } $element_twig->children('member') ],
                ];
            },
        },
    )->parse($xml);

    return @elements;
}

sub parse_common_element_data
{
    my ($element) = @_;
    return (
        element_type($element->gi),
        int $element->att('id'),
        int $element->att('version'),
        int $element->att('changeset'),
        str2time($element->att('timestamp')),
        int $element->att('uid'),
        $element->att('visible') eq 'true',
        { map { $_->att('k'), $_->att('v') } $element->children('tag') },
    );
}

# derived from osm-habat/osm-writer.mjs
#
# Outputs osm xml for provided elements in provided store.
# Output format: https://wiki.openstreetmap.org/wiki/OSM_XML
# Currently doesnt support writing deletes or deleted versions.
#
# @elements - Pre-sorted array of one of these:
#     [etype,eid,ev] - for writing existing version as unmodified
#     [etype,eid,ev,ev2] - for writing modifications (reverts) from existing version ev to existing version ev2
sub write_osm_file
{
    my ($filename, $data, @elements) = @_;

    open my $fh, '>:utf8', $filename or die $!;
    print $fh '<?xml version="1.0" encoding="UTF-8"?>'."\n";
    print $fh '<osm version="0.6" generator="'.xml_escape($OsmApi::agent).'">'."\n";
    foreach (@elements)
    {
        my ($e, $i, $v, $v2) = @$_;
        my $emeta = $data->{elements}[$e]{$i}{$v};
        my $edata = $emeta;
        my $is_modified = 0;
        if (defined($v2))
        {
            $edata = $data->{elements}[$e]{$i}{$v2};
            $is_modified = 1;
        }
        my $important_attrs = 'id="'.xml_escape($i).'" version="'.xml_escape($v).'"' .
            ' changeset="'.xml_escape($emeta->[CHANGESET]).'" uid="'.xml_escape($emeta->[UID]).'"'; # changeset and uid are required by josm to display element history
        $important_attrs .= ' action="modify"' if $is_modified;
        my $tags = $edata->[TAGS];
        if ($e == NODE)
        {
            print $fh '  <node '.$important_attrs.' lat="'.xml_escape($edata->[LAT]).'" lon="'.xml_escape($edata->[LON]).'"';
            if (!%$tags)
            {
                print $fh '/>'."\n";
            }
            else
            {
                print $fh '>'."\n";
                print_fh_tags($fh, $tags);
                print $fh '  </node>'."\n";
            }
        }
        elsif ($e == WAY)
        {
            print $fh '  <way '.$important_attrs.'>'."\n";
            print $fh '    <nd ref="'.xml_escape($_).'"/>'."\n" for @{$edata->[NDS]};
            print_fh_tags($fh, $tags);
            print $fh '  </way>'."\n";
        }
        elsif ($e == RELATION)
        {
            print $fh '  <relation '.$important_attrs.'>'."\n";
            for (@{$edata->[MEMBERS]})
            {
                my ($mt, $mi, $mr) = @$_;
                print $fh '    <member type="'.element_string($mt).'" ref="'.xml_escape($mi).'" role="'.xml_escape($mr).'"/>'."\n";
            }
            print_fh_tags($fh, $tags);
            print $fh '  </relation>'."\n";
        }
    }
    print $fh '</osm>'."\n";
    close $fh;
}

sub print_fh_tags
{
    my ($fh, $tags) = @_;
    print $fh '    <tag k="'.xml_escape($_).'" v="'.xml_escape($tags->{$_}).'"/>'."\n" for sort keys %$tags;
}

sub read_store_files
{
    my ($store_subdirname, $data) = @_;

    foreach my $changes_store_filename (glob qq{"$store_subdirname/*"})
    {
        print STDERR "reading store file $changes_store_filename\n" if $OsmApi::prefs->{'debug'};
        my $data_chunk = retrieve $changes_store_filename;
        OsmData::merge_data($data, $data_chunk);
    }
}

sub write_store_file
{
    my ($store_subdirname, $data_chunk) = @_;

    make_path $store_subdirname;
    my $fn = "00000000";
    $fn++ while -e "$store_subdirname/$fn";
    my $changes_store_filename = "$store_subdirname/$fn";
    print STDERR "writing store file $changes_store_filename\n" if $OsmApi::prefs->{'debug'};
    store $data_chunk, $changes_store_filename;
}

sub xml_escape
{
    my $s = shift;
    return encode_entities($s, '<>&"');
}

1;
