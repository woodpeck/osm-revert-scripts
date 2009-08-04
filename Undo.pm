#!/usr/bin/perl

# Undo.pm
# -------
#
# Implements undo operations
#
# Part of the "osmtools" suite of programs
# Originally written by Frederik Ramm <frederik@remote.org>; public domain

package Undo;

use strict;
use warnings;

use OsmApi;

# undoes one change by one user (or within one changeset)
#
# if the user has multiple changes at the current end of the 
# history, all of them are going to be undone (unless a 
# specific changeset is given). Likewise, if the object
# has been changed multiple times in the same changeset,
# then all of these changes will be reverted.
#
# fails if the object has been last changed by someone else.
#
# parameters: 
#   $what: 'node', 'way', or 'relation'
#   $id: object id
#   $undo_user: user whose operation should be undone
#      (this may also be a hash reference containing multiple user
#      names as keys, with any non-null value)
#      (this may be undef)
#   $undo_changeset: changeset whose operation should be undone
#      (this may also be a hash reference containing multiple changeset
#      ids as keys, with any non-null value)
#      (this may be undef)
#   $changeset: id of changeset to use for undo operation
# return:
#   success=1 failure=undef

sub undo
{
    my ($what, $id, $undo_user, $undo_changeset, $changeset) = @_;

    my ($action, $xml) = 
        determine_undo_action($what, $id, $undo_user, $undo_changeset, $changeset);

    return undef unless defined ($action);

    if ($action eq "modify")
    {
        my $resp = OsmApi::put("$what/$id", "<osm version='0.6'>\n$xml</osm>");
        if (!$resp->is_success)
        {
            print STDERR "$what $id cannot be uploaded: ".$resp->status_line."\n";
            return undef;
        }
    }
    elsif ($action eq "delete")
    {
        my $resp = OsmApi::delete("$what/$id", "<osm version='0.6'>$xml</osm>");
        if (!$resp->is_success)
        {
            print STDERR "$what $id cannot be deleted: ".$resp->status_line."\n";
            return undef;
        }
    }
    else
    {
        die "assertion failed";
    }
    return 1;
}

# the undo workhorse; finds out which XML to upload to the API to
# make a certain edit undone.
#
# Parameters:
# see sub undo.
#
# Returns:
# undef on error, else a two-element array where the first element is
# either "modify" or "delete" depending on the action to be taken, and
# the second element is the bare XML to send to the API. The XML has to 
# be wrapped in <osm>...</osm> or inside a <modify>...</modify> or
# <delete>...</delete> block in a changeset upload.

sub determine_undo_action
{
    my ($what, $id, $undo_users, $undo_changesets, $changeset) = @_;

    # backwards compatibility
    if (ref($undo_users) ne "HASH" && defined($undo_users))
    {
        $undo_users = { $undo_users => 1 };
    }

    if (ref($undo_changesets) ne "HASH" && defined($undo_changesets))
    {
        $undo_changesets = { $undo_changesets => 1 };
    }

    my $undo=0; 
    my $copy=0;
    my $out = "";
    my $lastedit;
    my $lastcs;
    my $undo_version;
    my $restore_version;

    my $resp = OsmApi::get("$what/$id/history");
    if (!$resp->is_success)
    {
        print STDERR "$what $id cannot be retrieved: ".$resp->status_line."\n";
        return undef;
    }

    foreach (split(/\n/, $resp->content()))
    { 
        if (/<$what/) 
        { 
            /\sid="([^"]+)"/ or die; 
                die unless $id eq $1; 
            /\sversion="([^"]+)"/ or die; 
                my $version = $1;
            /user="([^"]+)/;
            my $user=$1;
            /changeset="(\d+)/;
            my $cs=$1;
            if ((!defined($undo_users) || defined($undo_users->{$user})) && (!defined($undo_changesets) || defined($undo_changesets->{$cs})))
            { 
                $undo=1;
                $copy=0; 
                $undo_version = $version;
            } 
            else 
            {
                $lastedit = $user; 
                $lastcs = $cs;
                $undo=0; 
                $copy=1; 
                $out=$_ . "\n"; 
                $restore_version = $version;
            } 
        } 
        elsif ($copy) 
        { 
            $out.=$_ . "\n"; 
            $copy=0 if (/<\/$what/);
        } 
    }; 

    if ($undo)
    {
        if (length($out))
        {
            print STDERR "$what $id last edited as v$undo_version; restoring previous version $restore_version by '$lastedit'\n";
            $out =~ s/version="$restore_version"/version="$undo_version"/;
            $out =~ s/changeset="\d+"/changeset="$changeset"/;
            return ( "modify", $out );
        }
        else
        {
            print STDERR "$what $id was created; deleting\n";
            return ( "delete", "<$what id='$id' changeset='$changeset' version='$undo_version' lat='0' lon='0' />\n" );
        }
    }
    else
    {
        print STDERR "$what $id last edited in another changeset/by another user\n";
        return undef;
    }
}

1;
