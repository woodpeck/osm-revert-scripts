#!/usr/bin/perl

# Adapter script for Redaction.pm module
# exports Redaction.pm functionality for command line use.

use strict;
use Redaction;

if (($ARGV[0] eq "create") && (scalar(@ARGV) == 2))
{
    my $desc = "";
    while(<STDIN>) { $desc .= $_; }
    if (length($desc) == 0)
    {
    	print "usage: $0 create <title> < file-with-description\n";
        exit;
    }
    my $rd = Redaction::create($ARGV[1], $desc);
    print "redaction created: $rd\n" if defined($rd);
}
elsif (($ARGV[0] eq "update") && (scalar(@ARGV) == 3))
{
    my $desc = "";
    while(<STDIN>) { $desc .= $_; }
    if (length($desc) == 0)
    {
    	print "usage: $0 update <title> < file-with-description\n";
        exit;
    }
    my $rd = Redaction::update($ARGV[1], $ARGV[2], $desc);
    print "redaction updated: $rd\n" if defined($rd);
}
elsif (($ARGV[0] eq "apply") && (scalar(@ARGV) == 5 || scalar(@ARGV) == 4))
{
    shift @ARGV;
    my $rd = Redaction::apply(@ARGV);
    print "object redacted\n" if defined($rd);
}
elsif (($ARGV[0] eq "delete") && (scalar(@ARGV) == 2))
{
    if (Redaction::delete($ARGV[1]))
    {
        print "redaction deleted.\n";
    }
}
else
{
    print <<EOF;
Usage: 
  $0 create <title>      create redaction; description on stdin; returns id
  $0 update <id> <title> to update; provide description on stdin
  $0 delete <id>         to delete an (unused) redaction
  $0 apply <id> <objecttype> <objectid> <version> redact the specified object. If you omit <version>, starts at v1 and redacts all versions except the latest.
EOF
    exit;
}
