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

# Creates new changeset. 
# Parameters: none
# Returns: changeset id, or undef in case of error (will write error to stderr)

sub create($)
{
    my $comment = shift;
    $comment = (defined($comment)) ? "<tag k=\"comment\" v=\"$comment\" />" : "";
    my $resp = OsmApi::put("changeset/create", "<osm version='0.6'><changeset>$comment</changeset></osm>");
    if (!$resp->is_success)
    {
        print STDERR "cannot create changeset: ".$resp->status_line."\n";
        return undef;
    }
    return $resp->content();
}

# Closes changeset. 
# Parameters: changeset id, commit comment
# Returns: 1=success undef=error (will write error to stderr)

sub close($$)
{
    my ($id, $comment) = @_;
    $comment =~ s/&/&amp;/g;
    $comment =~ s/</&lt;/g;
    $comment =~ s/>/&gt;/g;
    $comment =~ s/"/&quot;/g;

    my $revision = '$Revision$';
    my $revno = 0;
    $revno = $1 if ($revision =~ /:\s*(\d+)/);

    my $resp = OsmApi::put("changeset/$id", <<EOF);
<osm version='0.6'>
<changeset>
<tag k='comment' v=\"$comment\" />
<tag k='created_by' v='osmtools/$revno ($^O)' />
</changeset>
</osm>
EOF
    if (!$resp->is_success)
    {
        print STDERR "cannot update changeset: ".$resp->status_line."\n";
        return undef;
    }
    $resp = OsmApi::put("changeset/$id/close");
    if (!$resp->is_success)
    {
        print STDERR "cannot close changeset: ".$resp->status_line."\n";
        return undef;
    }
    return 1;
}

sub upload($$)
{
    my ($id, $content) = @_;
    if (length($content) > 500000)
    {
       OsmApi::set_timeout(7200);
    }
    my $resp = OsmApi::post("changeset/$id/upload", $content);

    if (!$resp->is_success)
    {
        print STDERR "cannot upload changeset: ".$resp->status_line."\n";
        return undef;
    }
    return 1;
}

1;
