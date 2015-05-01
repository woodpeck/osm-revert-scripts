#!/usr/bin/perl

# Changeset.pm
# ------------
#
# Implements changeset operations on the OSM API
#
# Part of the "osmtools" suite of programs
# Originally written by Frederik Ramm <frederik@remote.org>; public domain

package Changeset;

use strict;
use warnings;
use OsmApi;
use URI::Escape;

# -----------------------------------------------------------------------------
# Creates new changeset. 
# Parameters: optionally, a comment
# Returns: changeset id, or undef in case of error (will write error to stderr)

sub create
{
    my $commit_comment = shift;

    my $resp = OsmApi::put("changeset/create", "<osm version='0.6'>".
        xmlnode(-1, $commit_comment). "</osm>");

    if (!$resp->is_success)
    {
        print STDERR "cannot create changeset: ".$resp->status_line."\n";
        return undef;
    }
    return $resp->content();
}


# -----------------------------------------------------------------------------
# Adds (discussion) comment to existing, closed changeset
# Parameters: changeset id, comment
# Returns: 1=ok, undef=error

sub comment($$)
{
    my ($id, $comment) = @_;
    $comment =~ s/&/&amp;/g;
    $comment =~ s/</&lt;/g;
    $comment =~ s/>/&gt;/g;
    $comment =~ s/"/&quot;/g;

    my $resp = OsmApi::post("changeset/$id/comment", "text=".uri_escape($comment));

    if (!$resp->is_success)
    {
        print STDERR "cannot comment on changeset: ".$resp->status_line."\n";
        return undef;
    }
}


# -----------------------------------------------------------------------------
# Creates XML representation of changeset
# Parameters: changeset id and optionally a comment
# Returns: the XML representation

sub xmlnode
{
    my ($id, $commit_comment) = @_;
    my $xml_comment = "";
    if (defined($commit_comment))
    {
        $commit_comment =~ s/&/&amp;/g;
        $commit_comment =~ s/</&lt;/g;
        $commit_comment =~ s/>/&gt;/g;
        $commit_comment =~ s/"/&quot;/g;
        $xml_comment = "<tag k='comment' v=\"$commit_comment\" />";
    }

    my $revision = '$Revision: 30252 $';
    my $revno = 0;
    $revno = $1 if ($revision =~ /:\s*(\d+)/);

    return <<EOF
<changeset id='$id'>
$xml_comment
<tag k='bot' v=\"yes\" />
<tag k='created_by' v='osmtools/$revno ($^O)' />
</changeset>
EOF
}


# -----------------------------------------------------------------------------
# Updates changeset metadata on server
# This would typically be used before closing to set a commit comment
# in case the comment wasn't set on opening already.
# Parameters: id of changeset, and optional comment
# Returns: 1=ok, undef=error

sub update($$)
{
    my ($id, $commit_comment) = @_;

    my $resp = OsmApi::put("changeset/$id", "<osm version='0.6'>".
        xmlnode($commit_comment)."</osm>");

    if (!$resp->is_success)
    {
        print STDERR "cannot update changeset: ".$resp->status_line."\n";
        print STDERR $resp->content;
        return undef;
    }

    return 1;
}


# -----------------------------------------------------------------------------
# Closes changeset. 
# Parameters: changeset id
# Returns: 1=success undef=error (will write error to stderr)

sub close($)
{
    my $id = shift;

    my $resp = OsmApi::put("changeset/$id/close");
    if (!$resp->is_success)
    {
        print STDERR "cannot close changeset: ".$resp->status_line."\n";
        return undef;
    }
    return 1;
}


# -----------------------------------------------------------------------------
# Uploads changeset.
# Paramters: changeset id, content
# replaces occurrences of changeset="something" with proper id
# Returns: 1=succes undef=error (will write to stderr)

sub upload($$)
{
    my ($id, $content) = @_;
    OsmApi::set_timeout(7200);
    $content =~ s/changeset="[^"]*"/changeset="$id"/g;
    my $resp = OsmApi::post("changeset/$id/upload", $content);

    if (!$resp->is_success)
    {
        print STDERR "cannot upload changeset: ".$resp->status_line."\n";
        print STDERR $resp->content."\n";
        return undef;
    }
    print STDERR $resp->content."\n";
    return 1;
}

1;
