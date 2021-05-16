#!/usr/bin/perl

# BatchRedaction.pm
# -----------------
#
# Implements redaction operations on the OSM API by reading element ids/versions from a file
#
# Part of the "osmtools" suite of programs
# public domain

package BatchRedaction;

use strict;
use warnings;
use OsmApi;

# -----------------------------------------------------------------------------
# Views specific versions of elements listed in a file
# Parameters: filename, request suffix
# request suffix is usually empty or ".json"
# Returns: 1 on success, undef on failure

sub view
{
    my ($filename, $suffix) = @_;
    $suffix //= "";
    open(FH, '<', $filename) or return undef;

    sub print_content
    {
        my ($content) = @_;
        chomp $content;
        print "$content\n\n";
    }

    while(<FH>)
    {
        chomp;
        my $resp = OsmApi::get($_.$suffix);
        my $code = $resp->code;
        if ($resp->is_success) {
            print "# $_ not redacted\n\n";
            print_content $resp->content;
        } elsif ($code == 404) {
            print "# $_ not found\n\n";
        } elsif ($code == 403) {
            my $resp2 = OsmApi::get($_.$suffix."?show_redactions=true");
            if ($resp2->is_success) {
                print "# $_ redacted and can be revealed\n\n";
                print_content $resp2->content;
            } else {
                print "# $_ redacted and cannot be revealed\n\n";
            }
        } else {
            print "# $_ encountered unknown error\n\n";
        }
    }

    close(FH);
    return 1;
}

# -----------------------------------------------------------------------------
# Redacts specific versions of elements listed in a file
# Parameters: filename, Redaction ID
# use empty redaction id to unredact
# Returns: 1 on success, undef on failure
# stops on the first failed redaction

sub apply
{
    my ($filename, $rid) = @_;

    my $done_exists = -e "$filename.done";
    my $left_exists = -e "$filename.left";
    if ($done_exists || $left_exists)
    {
        my $file_word = (($done_exists && $left_exists) ? "files" : "file");
        print "Cannot continue because $file_word produced by an interrupted batch redaction exist:\n";
        if ($done_exists)
        {
            print "    $filename.done with elements that have redaction calls completed\n";
            print "        - you may put this file away where you store completed redactions\n";
        }
        if ($left_exists)
        {
            print "    $filename.left with elements that have redaction calls failed or not attempted\n";
            print "        - you may replace the original file $filename with this one and run again\n";
        }
        print "Please review and rename/remove the $file_word before continuing.\n";
        return undef;
    }

    my $state = 1;
    my (@done_elements, @left_elements);

    local $SIG{INT} = sub {
        print " - interrupting on next element";
        $state = undef;
    };

    open(FH, '<', $filename) or return undef;
    while(<FH>)
    {
        chomp;

        if (!$state)
        {
            push @left_elements, $_;
            next;
        }

        print "redacting $_";
        my $path = "$_/redact";
        $path .= "?redaction=$rid" if defined $rid;
        my $resp = OsmApi::post($path);

        if ($resp->is_success)
        {
            print " - done\n";
            push @done_elements, $_;
        }
        else
        {
            print " - failed\n";
            push @left_elements, $_;
            my $m = $resp->content;
            $m =~ s/\s+/ /g;
            print STDERR "cannot redact $_: ".$resp->status_line.": $m\n";
            $state = undef;
        }
    }
    close(FH);

    sub write_elements_file
    {
        my ($output_filename, @output_elements) = @_;
        my $output_fh;

        return if (!@output_elements);
        if (!open $output_fh, '>', $output_filename)
        {
            print STDERR "cannot open interrupted batch redaction file $output_filename";
            return
        }
        foreach (@output_elements)
        {
            print $output_fh "$_\n";
        }
        close $output_fh;
    }

    if (!$state)
    {
        write_elements_file "$filename.done", @done_elements;
        write_elements_file "$filename.left", @left_elements;
    }

    return $state;
}

1;
