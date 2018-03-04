#!/usr/bin/perl

# Delete.pm
# ---------
#
# Deletes an object.
#
# Part of the "osmtools" suite of programs
# Originally written by Frederik Ramm <frederik@remote.org>; public domain
#


package Delete;

use strict;
use warnings;

use OsmApi;
use Redaction;

our $globalListOfDeletedStuff = {};

# deletes one object
#
# parameters: 
#   $what: 'node', 'way', or 'relation'
#   $id: object id
#   $changeset: id of changeset to use for delete operation
# return:
#   success=1 failure=undef

sub delete
{
    my ($what, $id, $changeset, $redaction) = @_;
    # this will try to remove not only the object but all its members
    # e.g. remove a way plus nodes
    my $recurse = 1;
    # this will try to modify any object that contains the object-to-be-deleted
    # by removing the object-to-be-deleted from it
    my $remove_references = 0;
    # this will delete all objects referencing the object-to-be-deleted.
    my $cascade = 0;

    my ($xml, $recurse_xml) = 
        determine_delete_action($what, $id, $changeset, $recurse, 0);
    return undef unless defined ($xml);

    my $modify = "";
    my $delete_cascade = "";
    my $loop = 1;
    while ($loop)
    {
        $loop = 0;
        my $osc = <<EOF;
<osmChange version='0.6'>
<modify>
$modify
</modify>
<delete>
$delete_cascade
</delete>
<delete>
$xml
</delete>
<delete if-unused="1">
$recurse_xml
</delete>
</osmChange>
EOF
        my $resp = OsmApi::post("changeset/$changeset/upload", $osc);
        if (!$resp->is_success)
        {
            my $c = $resp->content();
            print "$c\n";
            if ($c =~ /(\S+) (\d+) (is )?still used by (\S+) ([0-9,]+)/ || $c =~ /The (\S+) (\d+) (is )?used in (\S+) ([0-9,]+)/)
            {
                if ($remove_references)
                {
                    my ($what2, $id2, $referer, $referer_ids) = (lc($1),$2,$4,$5);
                    print STDERR "$what2 $id2 still used by $referer $referer_ids; removing it from there\n";
                    $referer = $1 if ($referer =~ /(.*)s$/);
                    foreach my $referer_id(split(/,/, $referer_ids))
                    {
                        my $obj = OsmApi::get("$referer/$referer_id");
                        foreach (split(/\n/, $obj->content()))
                        { 
                            next if (/<\?xml/);
                            next if (/<osm/);
                            next if (/<\/osm/);
                            next if (/<nd ref="$id2"/) && ($what2 eq "node");
                            next if (/<member type="$what2" ref="$id2"/);
                            s/changeset="\d+"/changeset="$changeset"/;
                            $modify .= $_;
                        }
                    }
                    $loop=1;
                }
                elsif ($cascade)
                {
                    my ($what2, $id2, $referer, $referer_ids) = (lc($1),$2,$4,$5);
                    print STDERR "$what2 $id2 still used by $referer $referer_ids; removing those\n";
                    $referer = $1 if ($referer =~ /(.*)s$/);
                    foreach my $referer_id(split(/,/, $referer_ids))
                    {
                        my $obj = OsmApi::get("$referer/$referer_id");
                        my $del;
                        foreach (split(/\n/, $obj->content()))
                        { 
                            next if (/<\?xml/);
                            next if (/<osm/);
                            next if (/<\/osm/);
                            next if (/<nd/);
                            next if (/<tag/);
                            next if (/<member/);
                            s/changeset="\d+"/changeset="$changeset"/;
                            $del .= $_;
                        }
                        $delete_cascade = $del.$delete_cascade;
                    }
                    $loop=1;
                }
            }
            else
            {
                print STDERR "$what $id cannot be deleted: ".$resp->status_line."\n";
                return undef;
            }
        }
    }

    if (defined($redaction))
    {
REDACT:
        foreach my $key(%$globalListOfDeletedStuff)
        {
            my ($what, $id) = ($key =~ /(\D+)(\d+)/);
            my $v = $globalListOfDeletedStuff->{$key};
            next unless (defined($v));
            for (my $i=$v; $i>0; $i--)
            {
                next REDACT unless Redaction::apply($redaction, $what, $id, $i);
                printf("redacted $what $id v$i\n");
            }
        }
    }

    return 1;
}

# the delete workhorse; finds out which XML to upload to the API to
# delete an object.
#
# Parameters:
# see sub delete.
#
# Returns:
# undef on error, else the new XML to send to the API.
# The XML has to 
# be wrapped in <osm>...</osm> or inside a <modify>...</modify>
# in a changeset upload.

sub determine_delete_action
{
    my ($what, $id, $changeset, $recursive, $indent) = @_;

    my $copy=0;
    my $out = "";
    my $recurse_out = "";
    my $members = [];
    my $version;
    my $user;

    my $resp = OsmApi::get("$what/$id");
    if (!$resp->is_success)
    {
        print STDERR " "x$indent;
        print STDERR "$what $id cannot be retrieved: ".$resp->status_line."\n";
        return undef;
    }

    my $c = $resp->content();

    foreach (split(/\n/, $resp->content()))
    { 
        if (/<$what/) 
        { 
            /\sid="([^"]+)"/ or die; 
            die unless $id eq $1; 
            /\sversion="([^"]+)"/ or die; 
            $version = $1;
            /user="([^"]+)/;
            $user=$1;
            $copy = 1;
            $out = $_;
            $out =~ s/">/"\/>/g;
            $members = [];
        } 
        elsif ($copy) 
        { 
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
    $globalListOfDeletedStuff->{$what.$id} = $version;

    print STDERR " "x$indent;
    print STDERR "$what $id last modified by $user (version $version) - deleting\n",
    $out =~ s/changeset="\d+"/changeset="$changeset"/;
    if ($recursive && scalar(@$members))
    {
        print STDERR " "x$indent;
        print STDERR "recursively deleting members of $what $id\n";
        foreach (@$members)
        {
            if (!defined($globalListOfDeletedStuff->{$_->{type}.$_->{id}}))
            {
                my ($a, $b) = determine_delete_action($_->{type}, $_->{id}, $changeset, 1, $indent + 2);
                $recurse_out = $recurse_out . $a . $b if defined($a);
            }
        }
    }
    return ($out, $recurse_out);
}

1;
