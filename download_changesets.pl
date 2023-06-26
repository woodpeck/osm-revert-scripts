#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long;

my $username;
my $uid;
my $since_date = "2001-01-01T00:00:00Z";
my $to_date;
my $output_dir;

GetOptions(
    "u:s" => \$username,
    "uid:i" => \$uid,
    "s:s" => \$since_date,
    "t:s" => \$to_date,
    "o:s" => \$output_dir
);

print "TODO ($username)($uid)($since_date)($to_date)($output_dir)\n";
