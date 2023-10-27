#!/usr/bin/perl

use strict;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long;
use OsmData;

my $cid;
my ($lat, $lon);
my $correct_options = GetOptions(
    "changeset|cid=s" => \$cid,
    "lat=s" => \$lat,
    "lon=s" => \$lon,
);

if (($ARGV[0] eq "create") && (scalar(@ARGV) == 1) && $correct_options)
{
    die "lat is missing" unless defined($lat);
    die "lon is missing" unless defined($lon);

    my $body;
    open my $fh, '>', \$body;
    OsmData::print_fh_xml_header($fh);
    OsmData::print_fh_element($fh, OsmData::NODE, undef, undef, [
        $cid, undef, undef, undef, {}, $lat * OsmData::SCALE, $lon * OsmData::SCALE
    ]);
    OsmData::print_fh_xml_footer($fh);
    close $fh;

    my $resp = OsmApi::put("node/create", $body);
    if (!$resp->is_success)
    {
        die "cannot create node: ".$resp->status_line."\n";
    }
    print "node created: ".$resp->content."\n";
    exit;
}

print "TODO commandline help\n";
