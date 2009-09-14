#!/usr/bin/perl

# Revert.pm
# ---------
#
# Implements whole changeset reverts
#
# Part of the "osmtools" suite of programs
# Originally written by Frederik Ramm <frederik@remote.org>; public domain

package Revert;

use strict;
use warnings;

use OsmApi;
use Undo;

# downloads a changeset and attempts to undo all changes
# within that. currently transaction-based, so the revert will 
# fail if it cannot be done cleanly, but see variable $transaction.
#
# parameters: 
#   $undo_changeset: the changeset to nuke
#   $changeset: the changeset in which the undo happens (must be open)
# return:
#   success=1 failure=undef

sub revert
{
    my ($undo_changeset, $changeset) = @_;

    my $resp = OsmApi::get("changeset/$undo_changeset/download");
    if (!$resp->is_success)
    {
        print STDERR "changeset $undo_changeset cannot be retrieved: ".$resp->status_line."\n";
        return undef;
    }

    my $objects = {};
    my $action;

    foreach (split(/\n/, $resp->content()))
    { 
        if (/<(modify|create|delete)/)
        {
            $action = $1;
        }
        elsif (/<(node|way|relation).*\sid=["'](\d+)["']/)
        {
            unshift(@{$objects->{"$action $1"}}, $2);
        }
    }

    # first undelete nodes, ways, relations;
    # then undo changes to nodes, ways, relations; 
    # then undo creations of relations, ways, nodes (note order).

    my $success = [];
    my $failure = [];
    # set this to 0 if you want individual API requests rather than a changeset
    # upload. this will be much slower but may be required if you cannot get all
    # changes through due to problems.
    my $transaction = 1;
    # set this to 1 if you have a large number of object creations. this will 
    # bypass requesting object history for those, and simply try and delete them.
    # which will fail if the object has been modified since.
    my $delete_shortcut = 0;
    my $oscpart;

    foreach my $operation("delete node", "delete way", "delete relation",
        "modify node", "modify way", "modify relation", 
        "create relation", "create way", "create node")
    {
        my $seen = {};

        foreach my $object(@{$objects->{$operation}})
        {
            # Do not process the same object in the same operation twice.
            # Allows the script to handle cases where a user has modified
            # an object twice in the same changeset.
	    next if exists $seen->{$object};
	    $seen->{$object} = 1;

            my ($what, $objtype) = split(/ /, $operation);
            if ($transaction)
            {
                # this collects all undos in one osc document.
                if (($delete_shortcut) && ($what eq "create"))
                {

                    print STDERR "$objtype $object created; shortcut deletion\n";
                    $oscpart->{"delete"} .= "<$objtype id=\"$object\" lat=\"0\" lon=\"0\" version=\"1\" changeset=\"$changeset\" />\n";
                }
                else
                {
                    my ($action, $xml) = Undo::determine_undo_action($objtype, $object, undef, $undo_changeset, $changeset);
                    return undef unless (defined($action));
                    $oscpart->{$action} .= $xml;
                }
            }
            else
            {
                # this does individual undo operations. currently unused!
                if (($delete_shortcut) && ($what eq "create"))
                {
                    print STDERR "$objtype $object created; shortcut deletion\n";
                    my $resp = OsmApi::delete("$objtype/$object", "<osm version='0.6'><$objtype id=\"$object\" lat=\"0\" lon=\"0\" version=\"1\" changeset=\"$changeset\" /></osm>");
                    if (!$resp->is_success)
                    {
                        push(@$failure, "$operation $object");
                    }
                    else
                    {
                        push(@$success, "$operation $object");
                    }
                }
                else
                {
                    if (Undo::undo($objtype, $object, undef, $undo_changeset, $changeset))
                    {
                        push(@$success, "$operation $object");
                    }
                    else
                    {
                        push(@$failure, "$operation $object");
                    }
                }
            }
        }
    }

    if ($transaction)
    {
        my $osc = "<osmChange version='0.6' generator='osmtools'>\n";
        foreach my $action("modify", "create", "delete")
        {
            if (defined($oscpart->{$action}))
            {
                $osc .= "<$action>\n".$oscpart->{$action}."</$action>\n";
            }
        }
        $osc .= "</osmChange>\n";
        my $res = OsmApi::post("changeset/$changeset/upload", $osc);
        if (!($res->is_success))
        {
            print STDERR "changeset upload failed: ".$res->status_line."\n";
            return undef;
        }
    }
    
    return 1;
}

1;
