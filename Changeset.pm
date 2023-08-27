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
use URI::Escape;

# -----------------------------------------------------------------------------
# Creates new changeset. 
# Parameters: optionally, a comment
# Returns: changeset id, or undef in case of error (will write error to stderr)

sub create
{
    my $commit_comment = shift;

    my $resp = OsmApi::put("changeset/create", "<osm version='0.6'>".
        xmlnode(-1, $commit_comment). "</osm>");

    if (!$resp->is_success)
    {
        print STDERR "cannot create changeset: ".$resp->status_line."\n";
        return undef;
    }
    return $resp->content();
}


# -----------------------------------------------------------------------------
# Adds (discussion) comment to existing, closed changeset
# Parameters: changeset id, comment
# Returns: 1=ok, undef=error

sub comment($$)
{
    my ($id, $comment) = @_;
    $comment =~ s/&/&amp;/g;
    $comment =~ s/</&lt;/g;
    $comment =~ s/>/&gt;/g;
    $comment =~ s/"/&quot;/g;

    my $resp = OsmApi::post("changeset/$id/comment", "text=".uri_escape($comment));

    if (!$resp->is_success)
    {
        print STDERR "cannot comment on changeset: ".$resp->status_line."\n";
        return undef;
    }
}


# -----------------------------------------------------------------------------
# Creates XML representation of changeset
# Parameters: changeset id and optionally a comment
# Returns: the XML representation

sub xmlnode
{
    my ($id, $commit_comment) = @_;
    my $xml_comment = "";
    if (defined($commit_comment))
    {
        $commit_comment =~ s/&/&amp;/g;
        $commit_comment =~ s/</&lt;/g;
        $commit_comment =~ s/>/&gt;/g;
        $commit_comment =~ s/"/&quot;/g;
        $xml_comment = "<tag k='comment' v=\"$commit_comment\" />";
    }

    my $revision = '$Revision: 30252 $';
    my $revno = 0;
    $revno = $1 if ($revision =~ /:\s*(\d+)/);

    return <<EOF
<changeset id='$id'>
$xml_comment
<tag k='bot' v=\"yes\" />
<tag k='created_by' v='osmtools/$revno ($^O)' />
</changeset>
EOF
}


# -----------------------------------------------------------------------------
# Updates changeset metadata on server
# This would typically be used before closing to set a commit comment
# in case the comment wasn't set on opening already.
# Parameters: id of changeset, and optional comment
# Returns: 1=ok, undef=error

sub update($$)
{
    my ($id, $commit_comment) = @_;

    my $resp = OsmApi::put("changeset/$id", "<osm version='0.6'>".
        xmlnode($id, $commit_comment)."</osm>");

    if (!$resp->is_success)
    {
        print STDERR "cannot update changeset: ".$resp->status_line."\n";
        print STDERR $resp->content;
        return undef;
    }

    return 1;
}


# -----------------------------------------------------------------------------
# Closes changeset. 
# Parameters: changeset id
# Returns: 1=success undef=error (will write error to stderr)

sub close($)
{
    my $id = shift;

    my $resp = OsmApi::put("changeset/$id/close");
    if (!$resp->is_success)
    {
        print STDERR "cannot close changeset: ".$resp->status_line."\n";
        return undef;
    }
    return 1;
}


# -----------------------------------------------------------------------------
# Uploads changeset.
# Paramters: changeset id, content
# replaces occurrences of changeset="something" with proper id
# Returns: 1=succes undef=error (will write to stderr)

sub upload($$)
{
    my ($id, $content) = @_;
    OsmApi::set_timeout(7200);
    $content =~ s/changeset="[^"]*"/changeset="$id"/g;
    my $resp = OsmApi::post("changeset/$id/upload", $content);

    if (!$resp->is_success)
    {
        print STDERR "cannot upload changeset: ".$resp->status_line."\n";
        print STDERR $resp->content."\n";
        return undef;
    }
    print STDERR $resp->content."\n";
    return 1;
}

# -----------------------------------------------------------------------------
# Downloads changeset.
# Paramters: changeset id
# Returns: changeset contents as string, undef on error

sub download($)
{
    my $csid = shift;
    my $resp = OsmApi::get("changeset/$csid/download");
    if (!$resp->is_success)
    {
        print STDERR "changeset $csid cannot be retrieved: ".$resp->status_line."\n";
        return undef;
    }
    return $resp->content();
}

# -----------------------------------------------------------------------------
# Get element versions from changeset content
# Paramters: changeset content
# Returns: array of type/id/version, undef on error
sub get_element_versions($)
{
    my ($content) = @_;
    my @element_versions = ();

    CORE::open my $fh, '<', \$content;
    while (<$fh>)
    {
        next unless /<(node|way|relation)/;
        my $type = $1;
        /id="(\d+)"/;
        my $id = $1;
        /version="(\d+)"/;
        my $version = $1;
        push @element_versions, "$type/$id/$version";
    }
    CORE::close $fh;
    return @element_versions;
}

# -----------------------------------------------------------------------------
# Get previous versions of elements, skipping newly created ones
# Paramters: array of type/id/version
# Returns: array of type/id/version, undef on error
sub get_previous_element_versions(@)
{
    my @element_versions = @_;
    my @previous_element_versions = ();

    iterate_over_element_versions(\@element_versions, sub {
        my ($type, $id, $version) = @_;
        $version -= 1;
        return if $version <= 0;
        push @previous_element_versions, "$type/$id/$version";
    });
    return @previous_element_versions;
}

# -----------------------------------------------------------------------------
# Get next versions of elements, skipping those at their top version
# Paramters: array of type/id/version
# Returns: array of type/id/version, undef on error
sub get_next_element_versions(@)
{
    my @element_versions = @_;
    
    my %type_id_versions = ();
    iterate_over_element_versions(\@element_versions, sub {
        my ($type, $id, $version) = @_;
        $type_id_versions{"$type/$id"} = $version;
    });

    my @queries = prepare_download_queries(0, @element_versions);
    my $top_content = run_download_queries("top", @queries);
    return undef unless defined($top_content);

    my @next_element_versions = ();
    my @top_element_versions = get_element_versions($top_content);
    iterate_over_element_versions(\@top_element_versions, sub {
        my ($type, $id, $next_version) = @_;
        my $version = $type_id_versions{"$type/$id"};
        if ($version < $next_version)
        {
            push @next_element_versions, "$type/$id/" . ($version + 1);
        }
    });
    return @next_element_versions;
}

sub download_elements(@)
{
    my @element_versions = @_;

    my @queries = prepare_download_queries(1, @element_versions);
    return run_download_queries("previous", @queries);
}

sub get_changeset_summary($)
{
    my ($content) = @_;
    my %counts = ();
    my %users = ();
    my %uids = ();

    CORE::open my $fh, '<', \$content;
    while (<$fh>)
    {
        next unless /<(node|way|relation)/;
        /changeset="([^"]*)"/;
        my $changeset = $1;
        $counts{$changeset}++;
        /user="([^"]*)"/;
        $users{$changeset} = $1;
        /uid="([^"]*)"/;
        $uids{$changeset} = $1;
    }
    CORE::close $fh;

    my @result;
    foreach my $changeset (sort { $b <=> $a } keys %counts)
    {
        push @result, $counts{$changeset} . "," . $changeset . "," . $uids{$changeset} . "," . $users{$changeset};
    }
    return @result;
}

###

sub prepare_download_queries($@)
{
    my $with_versions = shift;
    my @element_versions = @_;
    my %counts = ();
    my %ivs = ();
    my @queries = ();

    local *flush = sub($) {
        my ($type) = @_;
        push @queries, $type . "s?" . $type . "s=" . $ivs{$type};
        delete $counts{$type};
        delete $ivs{$type};
    };

    iterate_over_element_versions(\@element_versions, sub {
        my ($type, $id, $version) = @_;
        $counts{$type}++;
        $ivs{$type} .= "," if exists $ivs{$type};
        $ivs{$type} .= $id;
        $ivs{$type} .= "v" . $version if $with_versions;
        flush($type) if $counts{$type} > 700 || length($ivs{$type}) > 7500;
    });
    flush($_) for keys %counts;
    return @queries;
}

sub run_download_queries($@)
{
    my $relation = shift;
    my @queries = @_;

    my @contents = ();
    foreach my $query (@queries)
    {
        my $resp = OsmApi::get($query);
        if (!$resp->is_success)
        {
            print STDERR "$relation element versions cannot be retrieved: ".$resp->status_line."\n";
            return undef;
        }
        push @contents, $resp->content();
    }
    return merge_osm_contents(@contents);
}

sub merge_osm_contents(@)
{
    my @contents = @_;
    my $i = 0;
    my $result = $_;

    foreach my $content (@contents)
    {
        CORE::open my $fh, '<', \$content;
        while (<$fh>)
        {
            next if $i > 0 && /<\?xml/;
            next if $i > 0 && /<osm/;
            next if /<\/osm>/;
            $result .= $_;
        }
        CORE::close $fh;
        $i++;
    }
    $result .= "</osm>\n";
    return $result;
}

sub iterate_over_element_versions(\@&)
{
    my ($element_versions, $handler) = @_;
    foreach (@$element_versions)
    {
        next unless /(\w+)\/(\d+)\/(\d+)/;
        my $type = $1;
        my $id = $2;
        my $version = $3;
        $handler -> ($type, $id, $version);
    }
}

1;
