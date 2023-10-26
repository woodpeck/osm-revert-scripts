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
# (but see "force" flag)
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
#   success=1 failure=undef no action necessary=0

sub undo
{
    my ($what, $id, $undo_user, $undo_changeset, $undo_version, $changeset) = @_;

    my ($action, $xml) = 
        determine_undo_action($what, $id, $undo_user, $undo_changeset, $undo_version, $changeset);

    return 0 unless defined ($action);

    # set this to 1 if you want the undo script to trim ways or relations by
    # removing members that are unavailable
    my $use_available_members = 0;

    if ($action eq "modify")
    {
        my $resp = OsmApi::put("$what/$id", "<osm version='0.6'>\n$xml</osm>");
        if (!$resp->is_success)
        {
            if ($resp->code == 412 && $use_available_members && ($what ne "node"))
            {
                my $newxml = remove_unavailable_members($xml);
                if ($newxml ne $xml)
                {
                    $resp = OsmApi::put("$what/$id", "<osm version='0.6'>\n$newxml</osm>");
                    if (!$resp->is_success)
                    {
                        print STDERR "$what $id cannot be uploaded (after trimming): ".$resp->status_line."\n";
                        return 0;
                    }
                    print STDERR "$what $id successfully uploaded after trimming\n";
                    return 1;
                }
            }
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
            return ($resp->code == 410) ? 0 : undef;
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
    my ($what, $id, $undo_users, $undo_changesets, $undo_versions, $changeset) = @_;

    # backwards compatibility
    if (ref($undo_users) ne "HASH" && defined($undo_users))
    {
        $undo_users = { $undo_users => 1 };
    }

    if (ref($undo_changesets) ne "HASH" && defined($undo_changesets))
    {
        $undo_changesets = { $undo_changesets => 1 };
    }

    if (ref($undo_versions) ne "HASH" && defined($undo_versions))
    {
        $undo_versions = { $undo_versions => 1 };
    }

    my $undo=0; 
    my $copy=0;
    my $out = "";
    my $lastedit;
    my $lastcs;
    my $undo_version;
    my $restore_version;
    my $override_version;
    my $override = 0;
    my $force = 0; # if this is set to 1, any object touched by the undo userwill be reverted even if there are later modifications by others

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
            if ((!defined($undo_users) || defined($undo_users->{$user})) && (!defined($undo_changesets) || defined($undo_changesets->{$cs})) && (!defined($undo_versions) || defined($undo_versions->{$version})))
            { 
                $undo=1;
                $copy=0; 
                $undo_version = $version;
            } 
            else 
            {
                print "user=$user not in undo_users\ncs=$cs not in undo_cs\nver=$version not in undo_ver\n";
                if ($undo && $force)
                {
                    $override = 1;
                    $override_version = $version;
                }
                else
                {
                    $undo=0; 
                    $copy=1; 
                    $out=$_ . "\n"; 
                    $restore_version = $version;
                    $lastedit = $user; 
                    $lastcs = $cs;
                }
            } 
        } 
        elsif ($copy) 
        { 
            $out.=$_ . "\n"; 
            $copy=0 if (/<\/$what/);
        } 
    }; 

    if ($undo || $override)
    {
        if ($override)
        {
            $undo_version = $override_version unless ($undo_version > $override_version);
            print STDERR "$what $id: overriding subsequent changes\n";
        }
        if (length($out))
        {
            print STDERR "$what $id last edited as v$undo_version; restoring previous version $restore_version by '$lastedit'\n";
            $out =~ s/version="$restore_version"/version="$undo_version"/;
            $out =~ s/changeset="\d+"/changeset="$changeset"/;
            print STDERR $out;
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
        print STDERR "$what $id last edited in another changeset/by another user ($lastedit/$lastcs)\n";
        return undef;
    }
}

sub remove_unavailable_members
{
    my $xml = shift;
    my $out;
    foreach my $line(split(/\n/, $xml))
    {
        print STDERR ">>$line<<\n";
        if ($line =~ /nd ref="(\d+)"/)
        {
            $out .= $line."\n" if (OsmApi::exists("node/$1"));
        }
        elsif ($line =~ /member type="(\S+)" ref="(\d+)"/)
        {
            $out .= $line."\n" if (OsmApi::exists("$1/$2"));
        }
        else
        {
            $out .= $line."\n";
        }
    }
    return $out;
}
1;
