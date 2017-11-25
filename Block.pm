#!/usr/bin/perl

# Block.pm
# ------------
#
# Implements block operations on the OSM API
#
# Part of the "osmtools" suite of programs
# Originally written by Frederik Ramm <frederik@remote.org>; public domain

package Block;

use strict;
use warnings;
use OsmApi;
use URI::Escape;

# -----------------------------------------------------------------------------
# Creates new block. 
# Parameters: User name, reason for block, duration in hours, and 1/0 for "needs to log in"
# Returns: block id, or undef 

sub create
{
    my ($user, $reason, $duration, $needsview) = @_;

    my $resp = OsmApi::post_web("user_blocks", 
        "display_name=".uri_escape($user).
        "&user_block[reason]=".uri_escape($reason).
        "&user_block_period=".uri_escape($duration).
        "&user_block[needs_view]=".sprintf("%d", $needsview));

    if ($resp->content() =~ m!<div class="message">([^<]+)</div>!)
    {
        print "$1\n";
    }
    if ($resp->content() =~ m!<li><a href="/user_blocks/(\d+)/edit">!)
    {
        return $1;
    }
    return undef;
}

1;
