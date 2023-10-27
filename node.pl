#!/usr/bin/perl

use strict;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long;
use Node;

my $cid;
my ($lat, $lon);
my @keys;
my @values;
my $correct_options = GetOptions(
    "changeset|cid=i" => \$cid,
    "lat=f" => \$lat,
    "lon=f" => \$lon,
    "key=s" => \@keys,
    "value=s" => \@values,
);

if (($ARGV[0] eq "create") && (scalar(@ARGV) == 1) && $correct_options)
{
    die "lat is missing" unless defined($lat);
    die "lon is missing" unless defined($lon);
    die "different number of keys/values" unless @keys == @values;

    my %tags;
    @tags{@keys} = @values;
    my $id = Node::create($cid, \%tags, $lat, $lon);

    print "node created: $id\n" if defined($id);
    exit;
}

if (($ARGV[0] eq "modify") && (scalar(@ARGV) == 2) && $correct_options)
{
    my $id = $ARGV[1];
}

print <<EOF;
Usage: 
  $0 create <options>       create node
  $0 modify <id> <options>  modify node

options:
  --changeset
  --lat
  --lon
  --key
  --value
EOF
