#!/usr/bin/perl

# Note.pm
# -------
#
# Implements note operations on the OSM API
#
# Part of the "osmtools" suite of programs
# Originally written by Frederik Ramm <frederik@remote.org>; public domain

package Note;

use strict;
use warnings;
use OsmApi;
use URI::Escape;


# -----------------------------------------------------------------------------
# Hides the given note.
# Parameters: Note ID
# Returns: 1, or undef in case of error (will write error to stderr)
# (this API call requires moderator privilege)

sub hide
{
    my ($id) = @_;

    my $resp = OsmApi::delete("notes/$id", undef, 1);

    if (!$resp->is_success)
    {
        print STDERR "cannot hide note: ".$resp->status_line."\n";
        return undef;
    }
    return 1;
}

# -----------------------------------------------------------------------------
# Reopens the given note.
# Parameters: Note ID, comment text
# Returns: 1, or undef in case of error (will write error to stderr)

sub reopen
{
    my ($id, $text) = @_;
    return post("reopen", $id, $text);
}

sub close
{
    my ($id, $text) = @_;
    return post("close", $id, $text);
}

sub comment
{
    my ($id, $text) = @_;
    return post("comment", $id, $text);
}

sub post
{
    my ($endpoint, $id, $text) = @_;

    my $body;
    $body = "text=".uri_escape($text) if defined($text);
    my $resp = OsmApi::post("notes/$id/$endpoint", $body, 1);

    if (!$resp->is_success)
    {
        print STDERR "cannot $endpoint note: ".$resp->status_line."\n";
        return undef;
    }
    return 1;
}

sub get
{
    my ($id) = @_;
    my $resp = OsmApi::get("notes/$id", undef, 1);
    if (!$resp->is_success)
    {
        print STDERR "cannot load note: ".$resp->status_line."\n";
        return undef;
    }
    return $resp->content;
}

sub create
{
    my ($lat, $lon, $text) = @_;
    my $resp = OsmApi::post("notes", "lat=$lat&lon=$lon&text=".uri_escape($text));
    if (!$resp->is_success)
    {
        print STDERR "cannot create note: ".$resp->status_line."\n";
        return undef;
    }
    return $resp->content;
}
1;
