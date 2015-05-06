#!/usr/bin/perl

# Adapter script for Delete.pm module
# exports Delete.pm functionality for command line use.

use strict;
use warnings;
use Delete;
use Getopt::Long;

my $redaction; 

GetOptions("redact=i" => \$redaction);

if (scalar(@ARGV) != 3 || $ARGV[0] !~ /^(node|way|relation)$/)
{
    print <<EOF;
usage: $0 [--redact <rid>] <node|way|relation> <id> <changeset>

where 
  id : OSM id of the object to delete
  rid: id of the redaction used to redact this
  changeset : id of changeset to use for delete action
EOF
    exit;
}

my ($what, $id, $changeset) = @ARGV;

Delete::delete($what, $id, $changeset, $redaction);

