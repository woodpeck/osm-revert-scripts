#!/usr/bin/perl

# Modify.pm
# ---------
#
# Modifies the tags of an object.
#
# Part of the "osmtools" suite of programs
# Originally written by Frederik Ramm <frederik@remote.org>; public domain
#


package Modify;

use strict;
use warnings;

use OsmApi;
use Redaction;

# modifies one object
#
# parameters: 
#   $what: 'node', 'way', or 'relation'
#   $id: object id
#   $tags: hash of key=>value combinations (empty value for deleting a tag)
#   $changeset: id of changeset to use for modify operation
# return:
#   success=1 failure=undef

sub modify
{
    my ($what, $id, $tags, $changeset) = @_;

    my $copy=0;
    my $out = "";

    my $resp = OsmApi::get("$what/$id");
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
            $copy = 1;
            $out = $_;
        } 
        elsif ($copy) 
        { 
            $copy=0 if (/<\/$what/);
            if (/<tag k=\"([^"]*)" v="([^"]*)" *\/>/)
            {
                if (defined($tags->{$1}))
                {
                    if ($tags->{$1} ne "")
                    {
                        $out .= "<tag k=\"$1\" v=\"".$tags->{$1}."\" />\n";
                    }
                }
                else
                {
                    $out .= $_;
                }
            }
            else 
            {
                $out .= $_;
            }
        } 
    }; 
    return 1 if ($out eq $resp->content());

    $out =~ s/changeset="\d+"/changeset="$changeset"/;

    my $osc = <<EOF;
<osmChange version='0.6'>
<modify>
$out
</modify>
</osmChange>
EOF
    $resp = OsmApi::post("changeset/$changeset/upload", $osc);
    if (!$resp->is_success)
    {
        my $c = $resp->content();
        print "$c\n";
        print STDERR "$what $id cannot be modified: ".$resp->status_line."\n";
        return undef;
    }
    return 1;
}

1;
