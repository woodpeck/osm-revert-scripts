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
# Parameters: Redaction ID, object type, object id, object version
# Returns: 1 on success, undef on failure

sub apply
{
    my ($rid, $otype, $oid, $over) = @_;
    unless ($otype =~ /^(node|way|relation)$/)
    {
        print STDERR "invalid object type $otype\n";
        return undef;
    }

    my $resp = OsmApi::post("$otype/$oid/$over/redact?redaction=$rid");

    if (!$resp->is_success)
    {
        print STDERR "cannot redact $otype $oid v$over: ".$resp->status_line."\n";
        return undef;
    }
    return 1;
}

1;
