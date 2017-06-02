#!/usr/bin/perl

# Adapter script for Note.pm module
# exports Note.pm functionality for command line use.

use strict;
use Note;

if (($ARGV[0] eq "hide") && (scalar(@ARGV) == 2))
{
    my $r = Note::hide($ARGV[1]);
    print "note hidden: $r\n" if defined($r);
}
else
{
    print <<EOF;
Usage: 
  $0 hide <id>      hide note
EOF
    exit;
}
