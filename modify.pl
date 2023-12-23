#!/usr/bin/perl

# Adapter script for Modify.pm module
# exports Modify.pm functionality for command line use.

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Modify;
use Getopt::Long;

if (scalar(@ARGV) != 4 || $ARGV[0] !~ /^(node|way|relation)$/)
{
    print <<EOF;
usage: $0 <node|way|relation> <id> <key>=[<value>][,<key>=[<value>]...] <changeset> 

where 
  id : OSM id of the object to modify
  key=value : the tag to change (or delete, if value is empty)
  changeset : id of changeset to use for modify action
EOF
    exit;
}

my ($what, $id, $t, $changeset) = @ARGV;
my @tags = split(/,/, $t);
my $tags;
foreach (@tags)
{
    /(.*)=(.*)/ or die "cannot parse: $_";
    $tags->{$1}=$2;
}

Modify::modify($what, $id, $tags, $changeset);

