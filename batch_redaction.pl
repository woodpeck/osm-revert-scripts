#!/usr/bin/perl

use strict;
#use warnings;
use FindBin;
use lib $FindBin::Bin;
use OsmApi;

if (($ARGV[0] eq "view") && (scalar(@ARGV) == 2))
{
    open(FH, '<', $ARGV[1]) or die $!;

    while(<FH>)
    {
        chomp;
        print "viewing $_\n";
        my $resp = OsmApi::get($_);
        print $resp->content;
    }

    close(FH);
}
elsif (($ARGV[0] eq "apply") && (scalar(@ARGV) == 3))
{
    my $rid = $ARGV[2];
    open(FH, '<', $ARGV[1]) or die $!;

    while(<FH>)
    {
        chomp;
        print "redacting $_\n";
        my $resp = OsmApi::post("$_/redact?redaction=$rid");

        if (!$resp->is_success)
        {
            my $m = $resp->content;
            $m =~ s/\s+/ /g;
            print STDERR "cannot redact $_: ".$resp->status_line.": $m\n";
            last;
        }
    }

    close(FH);
}
else
{
    print <<EOF;
Usage: 
  $0 view <filename>          to view osm elements listed in file; each line is <otype>/<oid>/<oversion>
  $0 apply <filename> <id>    to do redactions from file; each line is <otype>/<oid>/<oversion>
EOF
    exit;
}
