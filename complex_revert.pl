#!/usr/bin/perl

# This program attempts to revert the sum of all edits in all
# .osc data read from stdin; typically, you would prepare a
# directory containing all changesets of one user and then do
#
# cat *.osc | perl complex_revert.pl
#
# The order on input is not relevant. Objects for which there's
# a "create" in the input will be deleted unless there's also a
# "delete" in the input. Objects modified in the input will be
# reset to one version before the first modification. Objects
# deleted in the input will also be reset similarly.

# This script will automatically open revert changesets.

# It will not revert objects where the newest version found on
# input is not current anymore (i.e. objects that have been
# modified in a changeset not given on input.

# Also, where the script decides to undelete something or revert
# something to an earlier state, and this is not possible because
# some of the member objects required have been deleted meanwhile,
# in changesets other than those given on input, the script will
# not attempt to undelete these members.

# Written by Frederik Ramm <frederik@remote.org>, public domain.

use Changeset;
use OsmApi;

use strict;

my $comment = "revert undiscussed building import"; # place your comment here

my $revert_type = "top_down"; # or bottom_up - see comments in code below

my $override = 0; # whether to override subsequent other changes

# no user servicable parts below

my $mode;
my $operation;
my $restore;
my $delete;
my $done;
my $current_cs;
my $current_count;
my $touched_cs = {};
my $used_cs = {};
my $done_count = 0;

die unless ($revert_type eq 'top_down' || $revert_type eq 'bottom_up');

open(LOG, "complex_revert.log");
while(<LOG>)
{
   my ($o, $i, $r) = split(/ /, $_);
   $done->{$o}->{$i} = 1;
   $done_count++
}
close(LOG);

print STDERR "$done_count object IDs read from complex_revert.log - will not touch these again\n";

open(LOG, ">> complex_revert.log");

# This initial reading step just catalogues operations that we've seen
# on which version of an object - in natural language, something like:
# "we've seen a delete for version 3 of node #123 and a modify for version
# 2 of the same node; we've seen a create for version 1 of way #234", etc.
#
# Results are record in the hash $operation, which for the above example
# would result in
#
# $operation = {
#    "node" => {
#       "123" => {
#          "2" => "modify",
#          "3" => "delete"
#       }
#    },
#    "way" => {
#       "234" => {
#          "1" => "create"
#       }
#    }
# }

while(<>)
{
    if (/<(create|modify|delete)>/)
    {
        $mode = $1;
    }
    elsif (/<(node|way|relation).*\sid="(\d+)"/)
    {
        my ($what, $id) = ($1, $2);
        /version="(\d+)"/;
        my $v = $1;
        /changeset="(\d+)"/;
        $touched_cs->{$1}=1;
        $operation->{$what}->{$id}->{$v} = $mode;
    }
}

# this part now looks at each individual object and determines what
# action needs to be taken in order to re-establish the status quo ante.
# we process all nodes first, then all ways, then all relations, although it
# doesn't really matter.

foreach my $objecttype(qw/node way relation/)
{  
    # process objects in each class in random order
    foreach my $id(keys %{$operation->{$objecttype}})
    {
        # for each object, determine the first and last version
        # (first = lowest version number, last = highest)
        # we have seen, as well as the corresponding first and
        # last operations.
        my $firstop;
        my $lastop;
        my @k = sort(keys(%{$operation->{$objecttype}->{$id}}));
        my $firstv = shift @k;
        my $lastv = pop @k;
        $lastv = $firstv if (!defined $lastv);
        my $firstop = $operation->{$objecttype}->{$id}->{$firstv};
        my $lastop = $operation->{$objecttype}->{$id}->{$lastv};

        if ($lastop eq "delete")
        {
            if ($firstop eq "create")
            {
                # ignore - object has been created and later deleted so we're fine
            }
            else
            {
                # object was deleted in the end, so revert to whatever it
                # was before first touched ($firstv is at least 2 else we'd
                # have been in the "firstop==create" branch).
                $firstv--;
                $restore->{$objecttype}->{$id} =  "$firstv/$lastv";
            }
        }
        elsif ($firstop eq "create")
        {
            # object was created, but not deleted later (else we'd habe been
            # in the branch above) - delete it.
            $delete->{$objecttype}->{$id} =  "$lastv";
        }
        else
        {
            # object was neither created nor deleted, just modified a number
            # of times (note: any intermediate delete followed by an undelete
            # would also end up here and be handled correctly). Revert to
            # whatever it was before first touched.
            $firstv--;
            $restore->{$objecttype}->{$id} =  "$firstv/$lastv";
        }
    }
}

# once we know what we want to do, we first handle all object modifications
# and undeletions that are recorded in the "restore" hash; there are two methods
# for this that only differ in ordering. after that, we handle all deletions.

if ($revert_type eq 'bottom_up')
{
    revert_bottom_up();
}
else
{
    revert_top_down();
}

handle_delete_soft();

Changeset::close($current_cs);

# We're done! Now just add comments to all the affected changesets.

my $msg = "This changeset has been reverted fully or in part by changeset";
$msg .= "s" if (scalar(keys(%$used_cs))>1);
$msg .= " ".join(", ", keys(%$used_cs));
$msg .= " where the changeset comment is: $comment";

foreach my $id(keys(%$touched_cs))
{
    Changeset::comment($id, $msg);
}

$msg = "This changeset reverts some or all edits made in changeset";
$msg .= "s" if (scalar(keys(%$touched_cs))>1);
$msg .= " ".join(", ", sort(keys(%$touched_cs)));
$msg .= ".";

foreach my $id(keys(%$used_cs))
{
    Changeset::comment($id, $msg);
}

# --------------------------------------------------------
# END OF MAIN PROGRAM
# --------------------------------------------------------

# revert_bottom_up is the simple method of reverting stuff - first,
# all nodes are reverted (which may include undeleting), then all ways,
# then all relations. The disadvantage of this is that if you have
# 10k delete ways with 100k deleted nodes, the whole process might take
# some time, and by the time you start undeleting ways, some mapper
# might have cleaned up your orphan nodes already.

sub revert_bottom_up
{
    $current_cs = Changeset::create($comment);
    $used_cs->{$current_cs} = 1;
    $current_count = 0;
    die ("revert_bottom_up doesn't yet support \$override, use revert_top_down") if ($override);
    foreach my $object(qw/node way relation/)
    {
        foreach my $id(keys %{$restore->{$object}})
        {
            my ($firstv, $lastv) = split("/", $restore->{$object}->{$id});
            my $resp = OsmApi::get("$object/$id/$firstv");
            if (!$resp->is_success)
            {
                print STDERR "cannot restore $object $id to version $firstv (get): ".$resp->status_line."\n";
                print LOG "$object $id ERR GET ".$resp->code." ".$resp->status_line."\n";
                next;
            }
            my $xml = $resp->content;
            $xml =~ s/changeset="\d+"/changeset="$current_cs"/;
            $xml =~ s/version="$firstv"/version="$lastv"/;
            $xml =~ s/visible="no"//;
            $resp = OsmApi::put("$object/$id", $xml);
            if (!$resp->is_success)
            {
                print STDERR "cannot restore $object $id to version $firstv (put): ".$resp->status_line."\n";
                my $b = $resp->content;
                $b =~ s/\s+/ /g;
                print LOG "$object $id ERR PUT ".$resp->status_line." $b\n";
                next;
            }
            print LOG "$object $id OK revert to v$firstv\n";

            if ($current_count++ > 40000)
            {
                Changeset::close($current_cs);
                $current_cs = Changeset::create($comment);
                $used_cs->{$current_cs} = 1;
                $current_count = 0;
            }
        }
    }
}

# revert_top_down attempts to process relation by relation and way by way,
# undeleting all child objects each time

sub revert_top_down
{
    $current_cs = Changeset::create($comment);
    $used_cs->{$current_cs} = 1;
    print LOG "changeset $current_cs created\n";
    $current_count = 0;
    foreach my $object(qw/relation way node/)
    {
        foreach my $id(keys %{$restore->{$object}})
        {
            next if defined($done->{$object}->{$id});
            my ($firstv, $lastv) = split("/", $restore->{$object}->{$id});
            revert_top_down_recursive($object, $id, $firstv, $lastv);
        }
    }
}

sub revert_top_down_recursive
{
    my ($object, $id, $firstv, $lastv) = @_;

    my $resp = OsmApi::get("$object/$id/$firstv");
    if (!$resp->is_success)
    {
        print STDERR "cannot restore $object $id to version $firstv (get): ".$resp->status_line."\n";
        print LOG "$object $id ERR GET ".$resp->status_line."\n";
        return;
    }

    my $xml = $resp->content;
    foreach (split(/\n/, $xml))
    {
        if (/<nd ref=.(\d+)/)
        {
            if (defined($restore->{'node'}->{$1}) && !defined($done->{'node'}->{$1}))
            {
                my ($fv, $lv) = split("/", $restore->{'node'}->{$1});
                revert_top_down_recursive('node', $1, $fv, $lv);
            }
        }
        elsif (/<member.*type=.(way|node|relation).*ref=.(\d+)/)
        {
            if (defined($restore->{$1}->{$2}) && !defined($done->{$1}->{$2}))
            {
                my ($fv, $lv) = split("/", $restore->{$1}->{$2});
                revert_top_down_recursive($1, $2, $fv, $lv);
            }
        }
    }

    $xml =~ s/changeset="\d+"/changeset="$current_cs"/;
    $xml =~ s/version="$firstv"/version="$lastv"/;
    $xml =~ s/visible="no"//;
    $resp = OsmApi::put("$object/$id", $xml);
    if (!$resp->is_success)
    {
        if ($override && ($resp->code == 409) && ($resp->content =~ /server had: (\d+)/))
        {
            my $curv = $1;
            $xml =~ s/version="$lastv"/version="$curv"/;
            $resp = OsmApi::put("$object/$id", $xml);
            if (!$resp->is_success)
            {
                print STDERR "cannot restore $object $id to version $firstv (despite override): ".$resp->status_line."\n";
            }
            else
            {
                print LOG "override later changes on $object $id\n";
            }
        }
        else
        {
            print STDERR "cannot restore $object $id to version $firstv (put): ".$resp->status_line."\n";
        }
        if (!$resp->is_success)
        {
            my $b = $resp->content;
            $b =~ s/\s+/ /g;
            print LOG "$object $id ERR PUT ".$resp->status_line." $b\n";
            return;
        }
    }
    print LOG "$object $id OK revert to v$firstv\n";

    # do this even on error, since retrying is no use?
    $done->{$object}->{$id} = 1;

    if ($current_count++ > 40000)
    {
        Changeset::close($current_cs);
    	print LOG "changeset $current_cs created\n";
        $current_cs = Changeset::create($comment);
        $used_cs->{$current_cs} = 1;
        $current_count = 0;
    }
    return;
}

sub handle_delete_soft
{
    foreach my $object(qw/relation way node/)
    {
        foreach my $id(keys %{$delete->{$object}})
        {
            my $lastv = $delete->{$object}->{$id};
            my $xml = "<osm generator=\"osmtools\"><$object id=\"$id\" version=\"$lastv\" lat=\"0\" lon=\"0\" changeset=\"$current_cs\" /></osm>";
            my $resp = OsmApi::delete("$object/$id", $xml);
            if (!$resp->is_success)
            {
                if ($override && ($resp->code == 409) && ($resp->content =~ /server had: (\d+)/))
                {
                    my $curv = $1;
                    $xml =~ s/version="$lastv"/version="$curv"/;
                    $resp = OsmApi::delete("$object/$id", $xml);
                    if (!$resp->is_success)
                    {
                        print STDERR "cannot delete $object $id (even after override): ".$resp->status_line."\n";
                    }
                    else
                    {
                        print LOG "override later changes on $object $id\n";
                    }
                }
                if (!$resp->is_success)
                {
                    print STDERR "cannot delete $object $id: ".$resp->status_line."\n";
                    my $b = $resp->content;
                    $b =~ s/\s+/ /g;
                    print LOG "$object $id ERR DELETE ".$resp->status_line." $b\n";
                    next;
                }
            }
            print LOG "$object $id OK delete\n";

            if ($current_count++ > 40000)
            {
                Changeset::close($current_cs);
                $current_cs = Changeset::create($comment);
                $used_cs->{$current_cs} = 1;
                print LOG "changeset $current_cs created\n";
                $current_count = 0;
            }
        }
    }
}

