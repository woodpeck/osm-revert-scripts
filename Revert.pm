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
use Changeset;

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
    my ($undo_changeset, $changeset, $comment) = @_;

    my $osc;
    if ($undo_changeset =~ /<osmChange/)
    {
        $osc = $undo_changeset;
        $undo_changeset = {};
        while($osc =~ /changeset="([^"]*)"/gs)
        {
            $undo_changeset->{$1}=1;
        }
        print "reverting changes from changesets: ".join(",", keys(%$undo_changeset))."\n";
    }
    else
    {
        $osc = Changeset::download($undo_changeset);
        return undef unless defined($osc);
    }

    my $objects = {};
    my $action;
    my $seen = {};

    foreach (split(/\n/, $osc))
    { 
        if (/<(modify|create|delete)/)
        {
            $action = $1;
        }
        elsif (/<(node|way|relation).*\sid=["'](\d+)["']/)
        {
            $seen->{$1.$2}++;
            # if an object appears for a second time, ignore it here.
            # but still count that it appeared twice.
            next if ($seen->{$1.$2} > 1);
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
    my $transaction = 0;
    # set this to 1 if you have a large number of object creations. this will 
    # bypass requesting object history for those, and simply try and delete them.
    # which will fail if the object has been modified since.
    my $delete_shortcut = 0;
    my $oscpart;

    foreach my $operation("delete node", "delete way", "delete relation",
        "modify node", "modify way", "modify relation", 
        "create relation", "create way", "create node")
    {
        printf("operation: $operation\n");

        foreach my $object(@{$objects->{$operation}})
        {
            my ($what, $objtype) = split(/ /, $operation);
            # this collects all undos in one osc document.
            if ($transaction)
            {
                # the delete shortcut is an optimisation where we don't
                # retrieve the object history. we can only do this if the
                # object has been created and not further modified in this
                # changeset.
                if (($delete_shortcut) && ($what eq "create") && $seen->{$objtype.$object} == 1)
                {

                    print STDERR "$objtype $object created; shortcut deletion\n";
                    $oscpart->{"delete"} .= "<$objtype id=\"$object\" lat=\"0\" lon=\"0\" version=\"1\" changeset=\"$changeset\" />\n";
                }
                # apart from the delete shortcut, we simply retrieve the
                # object history and see what we have to do to take the
                # object back to where it was before this changeset.
                else
                {
                    my ($action, $xml) = Undo::determine_undo_action($objtype, $object, undef, $undo_changeset, $changeset);
                    return undef unless (defined($action));
                    $oscpart->{$action} .= $xml;
                }
            }
            # this creates individual undo operations. currently unused!
            else
            {
                if (($delete_shortcut) && ($what eq "create") && $seen->{$objtype.$object} == 1)
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
                    if (Undo::undo($objtype, $object, undef, $undo_changeset, undef, $changeset))
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

    my $msg = "This changeset has been reverted fully or in part by changeset $changeset";
    if (defined($comment))
    {
        $msg .= " where the changeset comment is: $comment" 
    }
    else
    {
        $msg .= ".";
    }

    if (ref($undo_changeset) eq "")
    {
        Changeset::comment($undo_changeset, $msg);
    }
    else
    {
        foreach my $other(keys(%$undo_changeset))
        {
            Changeset::comment($other, $msg);
        }
    }
    
    return 1;
}

1;
