#!/usr/bin/perl

package Util;

use strict;
use warnings;

# tests if two OSM objects (in XML represenation) are the same,
# using a primitive "canonicalization"
sub object_equal
{
    my ($a, $b) = @_;
    return (canonicalize($a) eq canonicalize($b));
}

# primitive canonicalization of XML representation into a string
# that disregards ordering of tags, whitespace, and other unimportant
# stuff
sub canonicalize
{
    my $o = shift;
    my @unordered;
    my @ordered;
    foreach (split(/\n/, $o))
    {
        if (/nd\s+ref=['"](\d+)/)
        {
            push(@ordered, "n$1");
        }
        elsif (/member.*type=["']([^"']+)/)
        {
            my $t=$1;
            /ref=['"](\d+)/;
            my $i=$1;
            /role=['"]([^"']+)/;
            my $r=$1;
            push(@ordered, "m$t/$i/$r");
        }
        elsif (/<tag .*k=["']([^"']+)/)
        {
            my $k=$1;
            /v=['"]([^"']+)/;
            my $v=$1;
            push(@unordered, "t$k/$v");
        }
        elsif (/<(node|way|relation)/)
        {
            my $ty=$1;
            my $la = '';
            my $lo = '';
            my $vi = '';
            $la = $1 if (/lat=['"]([^"']+)/);
            $lo = $1 if (/lon=['"]([^"']+)/);
            $vi = $1 if (/visible=['"]([^"']+)/);
            push(@ordered, "$ty/$vi/$la/$lo");
        }
    }
    return join("::", @ordered) . "::" . join("::", sort(@unordered));
}

1;

