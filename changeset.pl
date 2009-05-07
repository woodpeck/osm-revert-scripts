#!/usr/bin/perl

# Adapter script for Changeset.pm module
# exports Changeset.pm functionality for command line use.

use strict;
use warnings;
use Changeset;

if ($ARGV[0] eq "create")
{
    my $cs = Changeset::create();
    print "changeset created: $cs\n" if defined($cs);
}
elsif (($ARGV[0] eq "close") && (scalar(@ARGV)==3))
{
    if (Changeset::close($ARGV[1], $ARGV[2]))
    {
        print "changeset closed.\n";
    }
}
else
{
    print "usage: $0 {create|close <id> <comment>}\n";
    exit;
}
