#!/usr/bin/perl

# Undelete.pm
# -----------
#
# Implements undelete operations. This is very much like Undo.pm; the differences
# are
#
# - undelete can only undo deletions, while undo can undo everything
# - on the other hand, undelete undoes *any* deletion while undo requires you to specify
#   which users's change you want to undo
# - undelete can work recursively (the default)
#
# Part of the "osmtools" suite of programs
# Originally written by Frederik Ramm <frederik@remote.org>; public domain

package Undelete;

use strict;
use warnings;

use OsmApi;

our $globalListOfUndeletedStuff = {};

# undeletes one object
#
# fails if the object is not deleted
#
# parameters: 
#   $what: 'node', 'way', or 'relation'
#   $id: object id
#   $changeset: id of changeset to use for undelete operation
# return:
#   success=1 failure=undef

sub undelete
{
    my ($what, $id, $changeset) = @_;
    my $recurse = 1;

    my $xml = determine_undelete_action($what, $id, $changeset, $recurse, 0);
    return undef unless defined ($xml);

    my $resp = OsmApi::post("changeset/$changeset/upload", "<osmChange version='0.6'>\n<modify>\n$xml</modify></osmChange>");
    if (!$resp->is_success)
    {
        print STDERR "$what $id cannot be undeleted: ".$resp->status_line."\n";
        return undef;
    }
    return 1;
}

# the undelete workhorse; finds out which XML to upload to the API to
# undelete an object.
#
# Parameters:
# see sub undelete.
#
# Returns:
# undef on error, else the new XML to send to the API.
# The XML has to 
# be wrapped in <osm>...</osm> or inside a <modify>...</modify>
# in a changeset upload.

sub determine_undelete_action
{
    my ($what, $id, $changeset, $recursive, $indent) = @_;

    my $copy=0;
    my $out = "";
    my $visible_version;
    my $visible_user;
    my $invisible_version;
    my $invisible_user;
    my $deleted;
    my $members = [];

    my $resp = OsmApi::get("$what/$id/history");
    if (!$resp->is_success)
    {
        print STDERR " "x$indent;
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
            /visible="([^"]+)/;
            my $visible=$1;
            if ($visible eq "true")
            { 
                $deleted = 0;
                $copy = 1;
                $visible_version = $version;
                $visible_user = $user;
                $out = $_;
                $members = [];
            } 
            else 
            {
                $invisible_user = $user;
                $invisible_version = $version;
                $deleted = 1;
                $copy = 0;
            } 
        } 
        elsif ($copy) 
        { 
            $out.=$_; 
            $copy=0 if (/<\/$what/);
            if (/<nd ref=.(\d+)/)
            {
                push(@$members, { type => "node", id => $1 });
            }
            elsif (/<member.*type=.(way|node|relation).*id=.(\d+)/)
            {
                push(@$members, { type => $1, id => $2 });
            }
        } 
    }; 

    if ($deleted)
    {
        print STDERR " "x$indent;
        print STDERR "$what $id deleted by user '$invisible_user'; restoring previous version $visible_version by '$visible_user'\n";
        $out =~ s/version="$visible_version"/version="$invisible_version"/;
        $out =~ s/changeset="\d+"/changeset="$changeset"/;
        if ($recursive && scalar(@$members))
        {
            print STDERR " "x$indent;
            print STDERR "recursively undeleting members of $what $id\n";
            foreach (@$members)
            {
                if (!defined($globalListOfUndeletedStuff->{$_->{type}.$_->{id}}))
                {
                    my $ua = determine_undelete_action($_->{type}, $_->{id}, $changeset, 1, $indent + 2);
                    $out = $ua . $out if defined($ua);
                    $globalListOfUndeletedStuff->{$_->{type}.$_->{id}} = 1;
                }
            }
        }
        return $out;
    }
    else
    {
        print STDERR " "x$indent;
        print STDERR "$what $id is not deleted\n";
        return undef;
    }
}

1;
