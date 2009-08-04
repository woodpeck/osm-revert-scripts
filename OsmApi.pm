#!/usr/bin/perl

# OsmApi.pm
# ---------
#
# Implements OSM API connectivity
#
# Part of the "osmtools" suite of programs
# Originally written by Frederik Ramm <frederik@remote.org>; public domain

package OsmApi;

use strict;
use warnings;
use LWP::UserAgent;

our $prefs;
our $ua;
our $dummy;

BEGIN
{

    $prefs = { "dryrun" => 1 };

    open (PREFS, $ENV{HOME}."/.osmtoolsrc") or die "cannot open ". $ENV{HOME}."/.osmtoolsrc";
    while(<PREFS>)
    {
        if (/^(\S+)\s*=\s*(\S*)/)
        {
            $prefs->{$1} = $2;
        }
    }
    close (PREFS);

    foreach my $required("username","password","apiurl")
    {
        die $ENV{HOME}."/.osmtoolsrc does not have $required" unless defined($prefs->{$required});
    }

    if (!defined($prefs->{instance}))
    {
        $prefs->{instance} = sprintf "%010x", $$ * rand(100000000);
        open(PREFS, ">>".$ENV{HOME}."/.osmtoolsrc");
        printf PREFS "instance=".$prefs->{instance};
        close(PREFS);
    }

    $prefs->{apiurl} =~ m!https?://([^/]+)/!;
    my $host = $1;
    $host .= ":80" unless ($host =~ /:/);
    $ua = LWP::UserAgent->new;
    $ua->credentials($host, "Web Password", $prefs->{username}, $prefs->{password});
    my $revision = '$Revision$';
    my $revno = 0;
    $revno = $1 if ($revision =~ /:\s*(\d+)/);
    $ua->agent("osmtools/$revno ($^O, ".$prefs->{instance}.")");
    $ua->timeout(600);

    $prefs->{debug} = $prefs->{dryrun} unless (defined($prefs->{debug}));

    $dummy = HTTP::Response->new(200);
}

sub get
{
    my $url = shift;
    my $req = HTTP::Request->new(GET => $prefs->{apiurl}.$url);
    my $resp = $ua->request($req);
    debuglog($req, $resp) if ($prefs->{"debug"});
    return($resp);
}

sub put
{
    my $url = shift;
    my $body = shift;
    if ($prefs->{dryrun})
    {
        printf STDERR "dry run (not executing): PUT ".$prefs->{apiurl}.$url."\n";
        printf STDERR "$body\n";
        return $dummy;
    }
    my $req = HTTP::Request->new(PUT => $prefs->{apiurl}.$url);
    $req->content($body) if defined($body);
    my $resp = $ua->request($req);
    debuglog($req, $resp) if ($prefs->{"debug"});
    return $resp;
}

sub post
{
    my $url = shift;
    my $body = shift;
    if ($prefs->{dryrun})
    {
        printf STDERR "dry run (not executing): POST ".$prefs->{apiurl}.$url."\n";
        return $dummy;
    }
    my $req = HTTP::Request->new(POST => $prefs->{apiurl}.$url);
    $req->content($body) if defined($body);
    my $resp = $ua->request($req);
    debuglog($req, $resp) if ($prefs->{"debug"});
    return $resp;
}

sub delete
{
    my $url = shift;
    my $body = shift;
    if ($prefs->{dryrun})
    {
        printf STDERR "dry run (not executing): DELETE ".$prefs->{apiurl}.$url."\n";
        printf STDERR "$body\n";
        return $dummy;
    }
    my $req = HTTP::Request->new(DELETE => $prefs->{apiurl}.$url);
    $req->content($body) if defined($body);
    my $resp = $ua->request($req);
    debuglog($req, $resp) if ($prefs->{"debug"});
    return $resp;
}

sub debuglog
{
    my ($request, $response) = @_;
    printf STDERR "%s %s... %s %s (%db)\n",
        $request->method(), 
        $request->uri(), 
        $response->code(), 
        $response->message(), 
        length($response->content());
}

1;
