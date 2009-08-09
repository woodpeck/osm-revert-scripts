#!/usr/bin/perl

# Adapter script for Changeset.pm module
# exports Changeset.pm functionality for command line use.

use strict;
use warnings;
use Changeset;

if ($ARGV[0] eq "create")
{
    my $cs = Changeset::create($ARGV[1]);
    print "changeset created: $cs\n" if defined($cs);
}
elsif (($ARGV[0] eq "close") && (scalar(@ARGV)==3))
{
    if (Changeset::close($ARGV[1], $ARGV[2]))
    {
        print "changeset closed.\n";
    }
}
elsif (($ARGV[0] eq "upload") && (scalar(@ARGV)==2))
{
    my $body = "";
    while(<STDIN>) { $body .= $_; }
    if (length($body) == 0)
    {
    	print "usage: $0 upload <id> < content-to-upload\n";
	exit;
    }
    if (Changeset::upload($ARGV[1], $body))
    {
        print "changeset uploaded.\n";
    }
}
else
{
    print "usage: $0 {create [<comment>] | close <id> <comment>}\n";
    exit;
}
