#!/usr/bin/perl

use strict;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long;
use Node;

my $latest_changeset = 0;
my $cid;
my $version;
my ($lat, $lon);
my @keys;
my @values;
my %tags;
my $correct_options = GetOptions(
    "changeset|cid=i" => \$cid,
    "latest-changeset!" => \$latest_changeset,
    "version=i" => \$version,
    "lat=f" => \$lat,
    "lon=f" => \$lon,
    "key=s" => \@keys,
    "value=s" => \@values,
);

if (($ARGV[0] eq "create") && (scalar(@ARGV) == 1) && $correct_options)
{
    process_arguments();
    my $id = Node::create($cid, \%tags, $lat, $lon);
    print "node created: $id\n" if defined($id);
    exit;
}

if (($ARGV[0] eq "overwrite") && (scalar(@ARGV) == 2) && $correct_options)
{
    die "--version required for updating" unless defined($version);
    process_arguments();
    my $id = $ARGV[1];
    my $new_version = Node::overwrite($cid, $id, $version, \%tags, $lat, $lon);
    print "node overwritten with version: $new_version\n" if defined($new_version);
    exit;
}

print <<EOF;
Usage: 
  $0 create <options>          create node
  $0 overwrite <id> <options>  overwrite node

options:
  --changeset=<id>             \\
  --latest-changeset           - need one
  --version=<number>           - required for updating
  --lat=<number>
  --lon=<number>
  --key=<string>               \\
  --value=<string>             - can have multiple
EOF

sub process_arguments
{
    die "need one of: (--latest-changeset, --changeset=<id>)" unless $latest_changeset || defined($cid);
    die "need only one of: (--latest-changeset, --changeset=<id>)" if $latest_changeset && defined($cid);
    if ($latest_changeset)
    {
        $cid = Node::get_latest_changeset();
        die unless defined($cid);
    }

    die "lat is missing" unless defined($lat);
    die "lon is missing" unless defined($lon);
    die "different number of keys/values" unless @keys == @values;

    @tags{@keys} = @values;
}
