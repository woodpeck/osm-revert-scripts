#!/usr/bin/perl

# Redaction.pm
# ------------
#
# Implements redaction operations on the OSM API
#
# Part of the "osmtools" suite of programs
# Originally written by Frederik Ramm <frederik@remote.org>; public domain

package Redaction;

use strict;
use warnings;
use OsmApi;
use URI::Escape;

# -----------------------------------------------------------------------------
# Creates new redaction. 
# Parameters: A title, and a description.
# Returns: redaction id, or undef in case of error (will write error to stderr)

sub create
{
    my ($title, $description) = @_;

    my $resp = OsmApi::load_web("redactions/new");

    if (!defined($resp))
    {
        print STDERR "cannot create redaction\n";
        return undef;
    }

    $resp = OsmApi::post_web("redactions", 
        "redaction%5Btitle=".uri_escape($title)."&redaction%5Bdescription=".uri_escape($description));

    if (!$resp->is_redirect)
    {
        print STDERR "cannot create redaction: ".$resp->status_line."\n";
        return undef;
    }
    return $resp->content();
}


# -----------------------------------------------------------------------------
# Updates title or description of an existing reaction.
# Parameters: Redaction ID, title, and a description.
# Returns: redaction id, or undef in case of error (will write error to stderr)

sub update
{
    my ($id, $title, $description) = @_;

    my $resp = OsmApi::post_web("redactions/$id", 
        "_method=patch&redaction%5Btitle=".uri_escape($title)."&redaction%5Bdescription=".uri_escape($description));

    if (!$resp->is_redirect)
    {
        print STDERR "cannot update redaction: ".$resp->status_line."\n";
        return undef;
    }
    return $resp->content();
}


# -----------------------------------------------------------------------------
# Deletes an (unused) redaction
# Parameters: Redaction ID
# Returns: redaction id, or undef in case of error (will write error to stderr)

sub delete
{
    my $id = shift;

    my $resp = OsmApi::load_web("redactions/$id");
    if (!defined($resp))
    {
        print STDERR "cannot delete redaction\n";
        return undef;
    }

    $resp = OsmApi::post_web("redactions/$id", "_method=delete");

    if (!$resp->is_redirect)
    {
        print STDERR "cannot delete redaction: ".$resp->status_line."\n";
        return undef;
    }
    return $resp->content();
}


# -----------------------------------------------------------------------------
# Redacts a specific version of an object
# Parameters: Redaction ID, object type, object id, object version or username
# if the last parameter is unset, redacts from v1 until current
# if the last parameter is set, but not in range 1...65536, it is assumed to be 
# an username and then only the version(s) edited by that user are redacted.
# Returns: 1 on success, undef on failure

sub apply
{
    my ($rid, $otype, $oid, $over) = @_;
    unless ($otype =~ /^(node|way|relation)$/)
    {
        print STDERR "invalid object type $otype\n";
        return undef;
    }

    if (defined($over) && ($over =~ /^\d+$/) && ($over>0) && ($over<=65536))
    {
        my $resp = OsmApi::post("$otype/$oid/$over/redact?redaction=$rid");

        if (!$resp->is_success)
        {
            my $m = $resp->content;
            $m =~ s/\s+/ /g;
            print STDERR "cannot redact $otype $oid v$over: ".$resp->status_line.": $m\n";
            return undef;
        }
        return 1;
    }
    elsif (defined($over))
    {
        my $resp = OsmApi::get("$otype/$oid/history");
        if (!$resp->is_success)
        {
            print STDERR "cannot get history for $otype $oid: ".$resp->status_line."\n";
            return undef;
        }
        my @versions_to_redact;
        my $err = 0;
        my $success = 0;

		foreach (split(/\n/, $resp->content()))
		{
			if (/<$otype.* user="([^"]*)"/)
			{
                next unless ($1 eq $over);
                push(@versions_to_redact, $1) if (/ version="(\d+)"/);
            }
        }

        foreach(@versions_to_redact)
        {
            my $resp = OsmApi::post("$otype/$oid/$_/redact?redaction=$rid");

            if (!$resp->is_success)
            {
                my $m = $resp->content;
                $m =~ s/\s+/ /g;
                print STDERR "cannot redact $otype $oid v$_: ".$resp->status_line.": $m\n";
                $err = 1;
            }
            else
            {
                $success++;
            }
        }
        return undef if ($success == 0);
        return undef if ($err);
        return 1;
    }
    else
    {
        $over = 1;
        while(1)
        {
            my $resp = OsmApi::post("$otype/$oid/$over/redact?redaction=$rid");

            if (!$resp->is_success)
            {
                return 1 if ($resp->code == 400);
                my $m = $resp->content;
                $m =~ s/\s+/ /g;
                print STDERR "cannot redact $otype $oid v$over: ".$resp->status_line.": $m\n";
                return undef;
            }
            $over++;
        }
    }
}

1;
