#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use OsmApi;

if ($ARGV[0] && (scalar(@ARGV) == 2))
{
    my $rid = $ARGV[0];
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
  $0 <id> <filename>     to do redactions from file; each line is <otype>/<oid>/<oversion>
EOF
    exit;
}
