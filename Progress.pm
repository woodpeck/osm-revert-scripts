#!/usr/bin/perl

# Progress.pm
# -----------
#
# Simple progress bar that doesn't require a fuckton of modules.
#
# Part of the "osmtools" suite of programs
# Originally written by Frederik Ramm <frederik@remote.org>; public domain

package Progress;

use strict;
use warnings;

# number of equal signs to use in the 100% progress bar
# (complete display line will be ~20 chars longer)
our $width = 50;

# no user servicable parts below

our $start_time = 0;
our $total = 0;
our $current;
our $last_update = 0;
our $last_bars = 0;
our $numwidth = 0;

BEGIN 
{
    # this requires unbuffered output
    $| = 1; 
}

# -----------------------------------------------------------------------------
# initialises progress bar
# Parameters: total number of operations (what is 100%)

sub init($)
{
    $start_time = time();
    $total = shift;
    $numwidth = length($total);
}

# -----------------------------------------------------------------------------
# updates progress bar
# Parameters: current number (-1 = 100%)

sub update($)
{
    $current = shift;
    $current = $total if ($current<0);
    my $now = time();
    my $bars = int($current * $width / $total);
    my $eta = "(wait)";
    my $elapsed = ($now - $start_time);
    if ($elapsed > 20)
    {
        my $remain = $elapsed / $current * $total - $elapsed;
        $eta = "";
        $eta = sprintf "%d:", $remain/3600 if ($remain>=3600);
        $eta .= sprintf "%02d:%02d ", ($remain%3600) / 60, $remain % 60;
        # need this to clean up stray characters after hour goes away
        $eta .= "  " unless ($remain>=3600);
    }
    if (($now - $last_update >= 1) || ($bars > $last_bars))
    {
        printf "[%*d/%*d] [%*s] ETA %s\r", 
            $numwidth, $current, 
            $numwidth, $total,
            -$width-1, '=' x $bars . '>',
            $eta;
    }
    $last_bars = $bars;
    $last_update = $now;
}

# -----------------------------------------------------------------------------
# outputs a log message without breaking the progress bar
# Parameters: message

sub log($)
{
    my $msg = shift;
    if (!defined($current))
    {
        print STDERR "$msg\n";
        return;
    }
    printf STDERR "%*s\n", -(20 + 2 * $numwidth + $width), $msg;
    $last_update = 0;
    update($current);
}

# -----------------------------------------------------------------------------
# outputs a log message without breaking the progress bar, then ends the program
# Parameters: message

sub die($)
{
    my $msg = shift;
    print STDERR "\n" if (defined($current));
    die($msg);
}

1;

