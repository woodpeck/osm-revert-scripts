#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use OsmApi;

if ($ARGV[0] && (scalar(@ARGV) == 1))
{
    my $rid = $ARGV[0];
    while(<STDIN>)
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
}
else
{
    print <<EOF;
Usage: 
  $0 <id>                to do redactions from stdin; each line is <otype>/<oid>/<oversion>
EOF
    exit;
}
