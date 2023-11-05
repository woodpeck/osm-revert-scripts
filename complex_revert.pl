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
# modified in a changeset not given on input).

# Also, where the script decides to undelete something or revert
# something to an earlier state, and this is not possible because
# some of the member objects required have been deleted meanwhile,
# in changesets other than those given on input, the script will
# not attempt to undelete these members.

# Written by Frederik Ramm <frederik@remote.org>, public domain.

use strict;
use FindBin;
use lib $FindBin::Bin;
use Changeset;
use OsmApi;
use Getopt::Long;
use Progress;
use Util;

my $override = 0;
my $show_conflict_details = 0;
my $revert_type = "bottom_up";
my $noprogress = 0;

usage() unless GetOptions("override" => \$override,
           "conflict-details" => \$show_conflict_details,
           "no-progress" => \$noprogress,
           "type=s" => \$revert_type);

usage() unless ($revert_type eq "top_down" || $revert_type eq "bottom_up");

my $progress = !$noprogress;
my $comment = $ARGV[0];
usage() if ($comment eq "");

# no user servicable parts below

sub usage()
{
    print STDERR <<EOF;
Usage: $0 [flags] comment
(expects full changesets to be reverted on stdin)
flags:
   --conflict-details   when revert fails due to version conflict, show other user
   --override           override subsequent changes in case of version conflict
   --progress           report on completion percentage
   --type=t             select revert type (default is top_down, otherwise bottom_up)
EOF
    exit 0;
}

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
my $max_changeset_size = 9000;
my $chunk_size = 500;

open(LOG, "complex_revert.log");
while(<LOG>)
{
   my ($o, $i, $r) = split(/ /, $_);
   $done->{$o}->{$i} = 1;
   $done_count++
}
close(LOG);

Progress::log("$done_count object IDs read from complex_revert.log - will not touch these again");

open(LOG, ">> complex_revert.log");

# This initial reading step just catalogues operations that we've seen
# on which version of an object - in natural language, something like:
# "we've seen a delete for version 3 of node #123 and a modify for version
# 2 of the same node; we've seen a create for version 1 of way #234", etc.
#
# Results are recorded in the hash $operation, which for the above example
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

while(<STDIN>)
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
        my @k = sort( { $a <=> $b } keys(%{$operation->{$objecttype}->{$id}}));
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
                # have been in the "firstop==create" branch above).
                $firstv--;
                $restore->{$objecttype}->{$id} =  "$firstv/$lastv";
            }
        }
        elsif ($firstop eq "create")
        {
            # object was created, but not deleted later (else we'd have been
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

# count stuff for progress bar

my $total_ops_done = 0;
if ($progress)
{
    my $total_ops_needed = 0;
    foreach my $objecttype(qw/node way relation/)
    {
        $total_ops_needed += scalar keys %{$restore->{$objecttype}};
        # deletions are faster, hence don't count them as full
        $total_ops_needed += 0.1*scalar keys %{$delete->{$objecttype}};
        # FIXME nodes are faster than ways, ways faster than relations...?
    }
    Progress::init($total_ops_needed)
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

if ($progress)
{
    Progress::update(-1);
    print "\n";
}

# We're done! Now just add comments to all the affected changesets.
#exit(0);

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
# 10k deleted ways with 100k deleted nodes, the whole process might take
# some time, and by the time you start undeleting ways, some mapper
# might have cleaned up your orphan nodes already.

sub revert_bottom_up
{
    $current_cs = Changeset::create($comment);
    $used_cs->{$current_cs} = 1;
    $current_count = 0;
    foreach my $object(qw/node way relation/)
    {
        # work in chunks of 500 objects because that is safe for a multi-fetch
        # (URL length limit)
        my @objects = keys %{$restore->{$object}};
        while(scalar @objects)
        {
            # chew off the first 500
            my @batch = splice(@objects, 0, 500);
            my $previous_content;

            while(1)
            {
                # fetch latest versions of these 500 from API
                my $resp = OsmApi::get("${object}s?${object}s=" . join(",", @batch));
                if (!$resp->is_success)
                {
                    Progress::die("cannot load batch of ${object}s: ".$resp->status_line);
                }

                # if we are in a repeat iteration, then we expect the response to
                # differ from before (else we'd loop endlessly). Need to strip off
                # the <osm> tag though because it contains a process ID in the
                # "generator" attribute and hence always differs.
                my $content_without_osm_tag = $resp->content;
                $content_without_osm_tag =~ s/<osm [^>]+>//;
                if ($content_without_osm_tag eq $previous_content)
                {
                    Progress::die("no new version information in repeated version download");
                }
                $previous_content = $content_without_osm_tag;
                my $current_versions = parse_multifetch_response($resp->content);

                # now, fetch the old version of each thing that we'd like to
                # go back to. the join/map construct picks the first number
                # before the slash from every v1/v2 combination.
                my $resp = OsmApi::get("${object}s?${object}s=" . join(",",
                    map({ my ($a,$b) = split("/", $restore->{$object}->{$_}); $_."v$a" } @batch)));
                if (!$resp->is_success)
                {
                    Progress::die("cannot load batch of ${object}s: ".$resp->status_line);
                }
                my $sane_versions = parse_multifetch_response($resp->content);

                # build a changeset that contains modifications
                my $osc = "";
                foreach my $id(@batch)
                {
                    my ($firstv, $lastv) = split("/", $restore->{$object}->{$id});

                    if ($sane_versions->{$id}->{'xml'} =~ /visible="false"/)
                    {
                        # the version we want to go to is deleted;
                        # which means we're wrong here. schedule for deletion.
                        # this might be better handled differently.
                        $delete->{$object}->{$id} =  "$lastv";
                        $total_ops_done--;
                        next;
                    }

                    if (Util::object_equal($current_versions->{$id}->{'xml'}, $sane_versions->{$id}->{'xml'}))
                    {
                        # no action needed.
                        print LOG "$object $id OK no action necessary to go from v$firstv to v$lastv\n";
                        next;
                    }

                    if ($lastv != $current_versions->{$id}->{'v'})
                    {
                        # version on server is higher than expected.
                        if ($override)
                        {
                            $lastv = $current_versions->{$id}->{'v'};
                            $current_versions->{$id}->{'xml'} =~ / user="([^"]+)"/;
                            Progress::log("interim modification by user $1 on $object $id - overriding");
                        }
                        else
                        {
                            $current_versions->{$id}->{'xml'} =~ / user="([^"]+)"/;
                            Progress::log("interim modification by user $1 on $object $id - skipping this");
                            next;
                        }
                    }
                    my $xml = $sane_versions->{$id}->{'xml'};
                    $xml =~ s/changeset="\d+"/changeset="$current_cs"/;
                    $xml =~ s/version="$firstv"/version="$lastv"/;
                    $osc .= $xml;
                    $current_count++;
                }
                if ($osc ne "")
                {
                    $osc = "<osmChange version='0.6'>\n<modify>\n" . $osc . "</modify>\n</osmChange>\n";
                    OsmApi::set_timeout(7200);
                    my $resp = OsmApi::post("changeset/$current_cs/upload", $osc);
                    if (!$resp->is_success)
                    {
                        if ($resp->code == 409)
                        {
                            # could be a version conflict. a re-run might fix the issue
                            next;
                        }
                        elsif ($resp->code == 412 && $resp->decoded_content =~ /(way|relation)\s+(\d+)\s+requires/mi)
                        {
                            my ($what, $which) = ($1, $2);
                            # referential integrity issue

                            Progress::log("precondition failed for $what $which, trying without");
                            @batch = grep { $_ != $which } @batch;
                            next;
                        }
                        else
                        {
                            Progress::die("cannot upload batch of objects: ".$resp->status_line."\n".$resp->decoded_content);
                        }
                    }
                }
                last;

            } # retry loop

            Progress::update($total_ops_done+=scalar(@batch)) if ($progress);

            foreach my $id(@batch)
            {
                my ($firstv, $lastv) = split("/", $restore->{$object}->{$id});
                print LOG "$object $id OK revert to v$firstv\n";
            }

            # ensure 500 places left in changeset
            if ($current_count > $max_changeset_size-500)
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

    Progress::update($total_ops_done++) if ($progress);
    my $resp = OsmApi::get("$object/$id/$firstv");
    if (!$resp->is_success)
    {
        Progress::log("cannot load version $firstv of $object $id (get): ".$resp->status_line);
        print LOG "$object $id ERR GET1 ".$resp->status_line."\n";
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

    # check if modification is required; current version might be identical to
    # what we're planning to revert to?
    my $resp = OsmApi::get("$object/$id/$lastv");
    if (!$resp->is_success)
    {
        Progress::log("cannot load version $lastv of $object $id (get): ".$resp->status_line);
        print LOG "$object $id ERR GET2 ".$resp->code." ".$resp->status_line."\n";
        return;
    }
    my $current = $resp->content;
    if (Util::object_equal($xml, $current))
    {
        print LOG "$object $id OK no action necessary to go from v$firstv to v$lastv\n";
        return;
    }

    if ($xml =~ /visible="false"/)
    {
        $delete->{$object}->{$id} =  "$lastv";
        next;
    }

    $xml =~ s/changeset="\d+"/changeset="$current_cs"/;
    $xml =~ s/version="$firstv"/version="$lastv"/;

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
                Progress::log("cannot restore $object $id to version $firstv (despite override): ".$resp->status_line);
            }
            else
            {
                print LOG "override later changes on $object $id\n";
            }
        }
        else
        {
            my $message = "cannot restore $object $id to version $firstv (put): ".$resp->status_line;
            if ($show_conflict_details)
            {
                my $b = $resp->content;
                if ($b =~ /server had: (\d+)/)
                {
                    my $resp = OsmApi::get("$object/$id/$1");
                    if ($resp->is_success)
                    {
                        my $cur_xml = $resp->content;
                        my $user;
                        $user = $1 if ($cur_xml =~ / user="([^"]*)"/);
                        $message .= " [interim ";
                        $message .= (Util::object_equal($xml, $cur_xml) ? "revert" : "modification");
                        $message .= " by $user]";
                        # fixme record this case as ok in complex_revert if interim revert
                    }
                }
            }
            Progress::log($message);
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

    if ($current_count++ > $max_changeset_size)
    {
        Changeset::close($current_cs);
    	print LOG "changeset $current_cs created\n";
        $current_cs = Changeset::create($comment);
        $used_cs->{$current_cs} = 1;
        $current_count = 0;
    }
    return;
}

sub ensure_room_in_cs
{
    my $room = shift;
    $room = 1 unless defined($room);
    if (($current_count + $room > $max_changeset_size) || (!defined($current_cs)))
    {
        if (defined($current_cs))
        {
            Changeset::close($current_cs);
    	    print LOG "changeset $current_cs closed\n";
        }
        $current_cs = Changeset::create($comment);
    	print LOG "changeset $current_cs created\n";
        $used_cs->{$current_cs} = 1;
        $current_count = 0;
    }
}

sub remaining_room_in_cs
{
    return $max_changeset_size - $current_count;
}

sub handle_delete_soft
{
    foreach my $object(qw/relation way node/)
    {
        my @idlist = keys %{$delete->{$object}};

        while(scalar(@idlist))
        {
            my $num_to_delete = remaining_room_in_cs();
            if ($num_to_delete < 1)
            {
                ensure_room_in_cs($chunk_size);
                $num_to_delete = $chunk_size;
            }
            my @to_process = splice(@idlist, 0, $num_to_delete);
            # Progress::log(sprintf("deleting a chunk of %d %s", scalar(@to_process), $object));
            Progress::update($total_ops_done+=0.1*scalar(@to_process)) if($progress);

            while(1)
            {
                my $c = "<osmChange version=\"0.6\">\n<delete if-unused=\"1\">\n";
                foreach my $i(@to_process)
                {
                    my $v = $delete->{$object}->{$i};
                    next unless defined($v);
                    $c .= "<$object id=\"$i\" changeset=\"$current_cs\" version=\"$v\" />\n";
                }
                $c .= "</delete>\n</osmChange>\n";
                OsmApi::set_timeout(7200);
                my $resp = OsmApi::post("changeset/$current_cs/upload", $c);

                if (!$resp->is_success)
                {
                    my $c = $resp->content;
                    if ($c =~ /Version mismatch: Provided \d+, server had: (\d+) of \S+ (\d+)/)
                    {
                        if ($override)
                        {
                            $delete->{$object}->{$2}=$1;
                            Progress::log("adjusted $object $2 version to $1");
                            next; # this repeats the action in the "while(1)" loop
                            # fixme - if this happens a lot then maybe the chunk should be split
                        } else {
                            delete $delete->{$object}->{$2}; # do not delete this object
                            Progress::log("excluded $object $2 from deletion");
                            next; # this repeats the action in the "while(1)" loop
                            # fixme - if this happens a lot then maybe the chunk should be split
                        }
                    }
                    else
                    {
                        Progress::die("cannot upload changeset: ".$resp->status_line);
                        # fixme should react to "precondition failed" or "gone" events by
                        # excluding object from batch rather than stopping
                    }
                }
                else
                {
                    $current_count += scalar(@to_process); # this may over-count because of if-unused
                    foreach my $i(@to_process)
                    {
                        print LOG "$object $i OK delete\n";
                    }
                    last; # breaks from the "while(1)" loop
                }
            }
        }
    }
}

sub get_user_for_object_version($)
{
    my $what = shift;
    my $resp = OsmApi::get($what);
    if ($resp->is_success)
    {
        my $xml = $resp->content;
        foreach (split(/\n/, $xml))
        {
            next unless(/<(node|way|relation)/);
            next unless(/user="([^"]*)"/);
            return $1;
            last;
        }
    }
    return undef;
}

sub parse_multifetch_response($)
{
    my $xml = shift;
    my $result = {};
    my $id;

    foreach (split(/\n/, $xml))
    {
        if (/<(node|way|relation)/)
        {
            / id="(\d+)"/ or die;
            $id = $1;
            / version="(\d+)"/ or die;
            my $version = $1;
            $result->{$id} = { 'v' => $version, 'xml' => '' };
        }
        $result->{$id}->{'xml'} .= "$_\n" if (defined($id) && !/<\/osm>/);
    }
    return $result;
}
