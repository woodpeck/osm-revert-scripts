#!/usr/bin/perl

package OsmData;

use Math::Round qw(round);
use HTTP::Date qw(str2time);
use XML::Twig;

use constant {
    NODE => 0,
    WAY => 1,
    RELATION => 2,
};
use constant {
    CHANGES => 0,
    DOWNLOAD_TIMESTAMP => 1,
};
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
use constant SCALE => 10000000;

sub element_type
{
    my ($type_string) = @_;
    return NODE if $type_string eq "node";
    return WAY if $type_string eq "way";
    return RELATION if $type_string eq "relation";
    die "unknown element type $type_string";
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

    my @changes = ();

    XML::Twig->new(
        twig_handlers => {
            node => sub {
                my($twig, $element) = @_;
                my ($type, $id, $version, @edata) = parse_common_element_data($element);
                push @changes, [$type, $id, $version];
                if ($edata[VISIBLE])
                {
                    push @edata,
                        round(SCALE * $element->att('lat')),
                        round(SCALE * $element->att('lon'));
                }
                $data->{elements}[$type]{$id}{$version} = \@edata;
            },
            way => sub {
                my($twig, $element) = @_;
                my ($type, $id, $version, @edata) = parse_common_element_data($element);
                push @changes, [$type, $id, $version];
                $data->{elements}[$type]{$id}{$version} = [
                    @edata,
                    [ map { int $_->att('ref') } $element->children('nd') ]
                ];
            },
            relation => sub {
                my($twig, $element) = @_;
                my ($type, $id, $version, @edata) = parse_common_element_data($element);
                push @changes, [$type, $id, $version];
                $data->{elements}[$type]{$id}{$version} = [
                    @edata,
                    [ map { [
                        element_type($_->att('type')),
                        int $_->att('ref'),
                        $_->att('role'),
                    ] } $element->children('member') ],
                ];
            },
        },
    )->parsefile($filename);

    $data->{changesets}{$id} = [
        \@changes,
        $timestamp,
    ];
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

1;
