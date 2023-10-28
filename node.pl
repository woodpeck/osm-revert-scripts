#!/usr/bin/perl

use strict;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long;
use Node;
use Changeset;

my $latest_changeset = 0;
my $new_changeset = 0;
my $cid;
my $latest_version = 0;
my $version;
my ($lat, $lon);
my @keys;
my @values;
my %tags;
my $correct_options = GetOptions(
    "changeset|cid=i" => \$cid,
    "latest-changeset!" => \$latest_changeset,
    "new-changeset!" => \$new_changeset,
    "version=i" => \$version,
    "latest-version!" => \$latest_version,
    "lat=f" => \$lat,
    "lon=f" => \$lon,
    "key=s" => \@keys,
    "value=s" => \@values,
);

if (($ARGV[0] eq "create") && (scalar(@ARGV) == 1) && $correct_options)
{
    process_arguments();
    require_latlon();
    my $id = Node::create($cid, \%tags, $lat, $lon);
    print "node created: $id\n" if defined($id);
    exit;
}

if (($ARGV[0] eq "overwrite") && (scalar(@ARGV) == 2) && $correct_options)
{
    my $id = $ARGV[1];
    process_arguments();
    require_latlon();
    require_value_or_latest("version", \$latest_version, \$version, sub { Node::get_latest_version($id) });
    my $new_version = Node::overwrite($cid, $id, $version, \%tags, $lat, $lon);
    print "node overwritten with version: $new_version\n" if defined($new_version);
    exit;
}

if (($ARGV[0] eq "delete") && (scalar(@ARGV) == 2) && $correct_options)
{
    my $id = $ARGV[1];
    process_arguments();
    require_value_or_latest("version", \$latest_version, \$version, sub { Node::get_latest_version($id) });
    my $new_version = Node::delete($cid, $id, $version);
    print "node deleted with version: $new_version\n" if defined($new_version);
    exit;
}

print <<EOF;
Usage: 
  $0 create <options>          create node
  $0 overwrite <id> <options>  create new node version discarding all previous data
  $0 delete <id> <options>     delete node

options:
  --changeset=<id>             \\
  --latest-changeset           - need one
  --new-changeset              /
  --version=<number>           \\
  --latest-version             - need one for updating
  --lat=<number>
  --lon=<number>
  --key=<string>               \\
  --value=<string>             - can have multiple
EOF

sub process_arguments
{
    die "need exactly one of: (--latest-changeset, --new-changeset, --changeset=<id>)" unless $latest_changeset + $new_changeset + defined($cid) == 1;
    $cid = Node::get_latest_changeset() if $latest_changeset;
    $cid = Changeset::create() if $new_changeset;
    die unless defined($cid);

    die "different number of keys/values" unless @keys == @values;
    @tags{@keys} = @values;
}

sub require_latlon
{
    die "lat is missing" unless defined($lat);
    die "lon is missing" unless defined($lon);
}

sub require_value_or_latest
{
    my ($name, $latest_ref, $value_ref, $getter) = @_;

    die "need one of: (--latest-$name, --$name=<n>)" unless $$latest_ref || defined($$value_ref);
    die "need only one of: (--latest-$name, --$name=<n>)" if $$latest_ref && defined($$value_ref);
    if ($$latest_ref)
    {
        $$value_ref = $getter->();
        die unless defined($$value_ref);
    }
}
