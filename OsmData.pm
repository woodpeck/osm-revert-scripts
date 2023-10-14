#!/usr/bin/perl

package OsmData;

use Math::Round qw(round);
use HTTP::Date qw(str2time);
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
};

sub read_store_files
{
    my ($store_dirname, $subdirname) = @_;

    my $data = OsmData::blank_data();
    if (defined($store_dirname)) {
        foreach my $changes_store_filename (glob qq{"$store_dirname/$subdirname/*"})
        {
            print STDERR "reading store file $changes_store_filename\n" if $OsmApi::prefs->{'debug'};
            my $data_chunk = retrieve $changes_store_filename;
            OsmData::merge_data($data, $data_chunk);
        }
    }

    return $data;
}

sub write_store_file
{
    my ($store_dirname, $subdirname, $data_chunk) = @_;

    make_path "$store_dirname/$subdirname";
    my $fn = "00000000";
    $fn++ while -e "$store_dirname/$subdirname/$fn";
    my $new_changes_store_filename = "$store_dirname/$subdirname/$fn";
    print STDERR "writing store file $new_changes_store_filename\n" if $OsmApi::prefs->{'debug'};
    store $data_chunk, $new_changes_store_filename;
}

1;
