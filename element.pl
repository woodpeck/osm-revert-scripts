#!/usr/bin/perl

use strict;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long;
use Changeset;
use Element;

my $new_changeset = 0;
my $cid;
my $reset = 0;
my ($version, $to_version);
my $to_previous_version = 0;
my ($lat, $lon);
my $latlon;
my ($nodes_arg, @nodes, @node_strings);
my ($members_arg, @members);
my (@keys, @values, @tags, @tag_strings);
my (@delete_keys, @delete_values, @delete_tags, @delete_tag_strings);
my %tags;
my %delete_tags;
my $correct_options = GetOptions(
    "changeset|cset|cid=i" => \$cid,
    "new-changeset|new-cset!" => \$new_changeset,
    "version=i" => \$version,
    "to-version=i" => \$to_version,
    "to-previous-version|to-prev-version!" => \$to_previous_version,
    "reset!" => \$reset,
    "lat=f" => \$lat,
    "lon=f" => \$lon,
    "latlon|ll=s" => \$latlon,
    "node|nd=i" => \@nodes,
    "nodes|nds=s" => \@node_strings,
    "member=s" => \@members,
    "key=s" => \@keys,
    "value=s" => \@values,
    "tag=s" => \@tags,
    "tags=s" => \@tag_strings,
    "delete-key|del-key=s" => \@delete_keys,
    "delete-value|del-value=s" => \@delete_values,
    "delete-tag|del-tag=s" => \@delete_tags,
    "delete-tags|del-tags=s" => \@delete_tag_strings,
);

my ($id, $type);

if (($ARGV[0] eq "browse") && $correct_options)
{
    require_type_and_id();
    Element::browse($type, $id);
    exit;
}

if (($ARGV[0] eq "create") && $correct_options)
{
    require_type();
    process_arguments();
    require_latlon() if $type eq "node";
    $id = Element::create($cid, $type, \%tags, $lat, $lon, $nodes_arg, $members_arg);
    print "$type created: $id\n" if defined($id);
    exit;
}

if (($ARGV[0] eq "delete") && $correct_options)
{
    require_type_and_id();
    process_arguments();
    require_version();
    my $new_version = Element::delete($cid, $type, $id, $version);
    print "$type deleted with version: $new_version\n" if defined($new_version);
    exit;
}

if (($ARGV[0] eq "modify") && $correct_options)
{
    require_type_and_id();
    process_arguments();
    require_version();
    if ($to_previous_version)
    {
        die "can't go to previous version from version $version" if $version <= 1;
        $to_version = $version - 1;
    }
    die "can't have both to-version and reset" if defined($to_version) && $reset;
    require_latlon() if $reset;
    my $new_version = Element::modify($cid, $type, $id, $version, $to_version, $reset, \%tags, \%delete_tags, $lat, $lon, $nodes_arg, $members_arg);
    print "$type overwritten with version: $new_version\n" if defined($new_version);
    exit;
}

print <<EOF;
Usage:
  $0 browse <type> <id>              open osm element in web browser
  $0 create <type> <options>         create osm element
  $0 delete <type> <id> <options>    delete osm element
  $0 modify <type> <id> <options>    modify the existing osm element version

type:
  node or way
  type+id can be shortened to letter+number like this: n12345

options:
  --changeset=<id>                 use specified changeset
  --new-changeset                  open new changeset
                                   else use latest changeset
  --version=<number>               update this verion or fail with edit conflict
                                   else update the latest version
  --to-version=<number>
  --to-previous-version
  --reset                          delete everything from the element prior to modification
  --lat=<number>                   node latitude
  --lon=<number>                   node longitude
  --ll=<number,number>             shortcut for --lat=<number> --lon=<number>

options that can be passed repeatedly:
  --node=<id>                      way node
  --nodes=<id>[,<id>...]           way nodes
  --member=<type>,<id>,<role>      relation member
  --key=<string>
  --value=<string>
  --tag=<key>[=<value>]            shortcut for --key=<key> --value=<value>
  --tags=<key>=[<value>][,<key>=[<value>]...]
  --delete-key=<string>
  --delete-value=<string>
  --delete-tag=<key>[=<value>]      if value is specified, delete tag if both key and value match
  --delete-tags=<key>=[<value>][,<key>=[<value>]...]
EOF

sub require_type
{
    die "element type required" unless defined($ARGV[1]);
    parse_type_value($ARGV[1]);
}

sub require_type_and_id
{
    die "element type required" unless defined($ARGV[1]);
    if ($ARGV[1] =~ /^([a-z]+)(\d+)$/)
    {
        parse_type_value($1);
        $id = $2;
    }
    else
    {
        parse_type_value($ARGV[1]);
        die "element id required" unless defined($ARGV[2]);
        $id = $ARGV[2];
    }
}

sub parse_type_value
{
    my ($type_value) = @_;
    foreach ("node", "way", "relation")
    {
        $type = $_ if rindex($_, $type_value, 0) == 0;
    }
    die "invalid element type '$type_value'" unless defined($type);
}

sub process_arguments
{
    my $type = $ARGV[1];
    my $id = $ARGV[2];

    if (defined($cid))
    {
        die "can't have both specified and new changeset" if $new_changeset;
    }
    elsif ($new_changeset)
    {
        $cid = Changeset::create();
    }
    else
    {
        $cid = Element::get_latest_changeset();
    }
    die unless defined($cid);

    if (defined($latlon))
    {
        die "can't have both --lat and --latlon" if defined($lat);
        die "can't have both --lon and --latlon" if defined($lat);
        ($lat, $lon) = split /,/, $latlon, 2;
    }

    if (@nodes || @node_strings)
    {
        $nodes_arg = [];
        push @$nodes_arg, @nodes;
        push @$nodes_arg, map { split /,/ } @node_strings;
    }

    if (@members)
    {
        $members_arg = [];
        push @$members_arg, map { [split /,/, $_, 3] } @members;
    }

    %tags = process_tags("keys/values", \@keys, \@values, \@tags, \@tag_strings);
    %delete_tags = process_tags("delete-keys/values", \@delete_keys, \@delete_values, \@delete_tags, \@delete_tag_strings);
}

sub process_tags
{
    my ($name, $keys, $values, $tags, $tag_strings) = @_;
    die "different number of $name" unless @$keys == @$values;
    my %tags = map { split /=/, $_, 2 } (@$tags, map { split /,/ } @$tag_strings);
    @tags{@$keys} = @$values;
    return %tags;
}

sub require_latlon
{
    die "lat is missing" unless defined($lat);
    die "lon is missing" unless defined($lon);
}

sub require_version
{
    $version = Element::get_latest_version($type, $id) unless defined($version);
    die unless defined($version);
}
