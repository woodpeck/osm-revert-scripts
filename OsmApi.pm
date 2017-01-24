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
use MIME::Base64;
use HTTP::Cookies;
use URI::Escape;

our $prefs;
our $ua;
our $dummy;
our $noversion;
our $cookie_jar;
our $auth_token;

BEGIN
{

    $prefs = { "dryrun" => 1 };

    open (PREFS, $ENV{HOME}."/.osmtoolsrc") or die "cannot open ". $ENV{HOME}."/.osmtoolsrc";
    while(<PREFS>)
    {
        if (/^([^=]*)=(.*)/)
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
    my $revision = '$Revision: 30253 $';
    my $revno = 0;
    $revno = $1 if ($revision =~ /:\s*(\d+)/);
    $ua->agent("osmtools/$revno ($^O, ".$prefs->{instance}.")");
    $ua->timeout(600);

    $prefs->{debug} = $prefs->{dryrun} unless (defined($prefs->{debug}));

    $dummy = HTTP::Response->new(200);

    $prefs->{'weburl'} = $prefs->{'apiurl'};
    if ($prefs->{'weburl'} =~ /(.*\/)api\/0.6\//)
    {
        $prefs->{'weburl'} = $1;
    }
}

sub login
{
    $ua->cookie_jar($cookie_jar = HTTP::Cookies->new());
    my $resp = $ua->get($prefs->{'weburl'}."login");
    die unless($resp->is_success);
    my $cont = $resp->content;
    die unless($cont =~ /<meta name="csrf-token" content="(.*)" \/>/);
    $auth_token = $1;
    $resp = $ua->post($prefs->{'weburl'}."login", {
        "authenticity_token" => $auth_token,
        "utf8" => "\x{2713}",
        "referer" => "",
        "commit" => "Login",
        "username" => $prefs->{'username'}, 
        "password" => $prefs->{'password'}});
    die unless($resp->is_redirect);
}

sub load_web
{
    my $form = shift;
    login() unless defined($cookie_jar);
    my $resp = $ua->get($prefs->{'weburl'}.$form);
    return undef unless($resp->is_success);
    my $cont = $resp->content;
    return undef unless($cont =~ /<meta name="csrf-token" content="(.*)" \/>/);
    $auth_token = $1;
    return 1;
}

sub repeat
{
    my $req = shift;
    my $resp;
    for (my $i=0; $i<3; $i++)
    {
        $resp = $ua->request($req);
        return $resp unless ($resp->code == 502 || $resp->code == 500);
        sleep 1;
    }
    return $resp;
}

sub get
{
    my $url = shift;
    my $req = HTTP::Request->new(GET => $prefs->{apiurl}.$url);
    my $resp = repeat($req);
    debuglog($req, $resp) if ($prefs->{"debug"});
    return($resp);
}

sub exists
{
    my $url = shift;
    my $req = HTTP::Request->new(HEAD => $prefs->{apiurl}.$url);
    my $resp = repeat($req);
    debuglog($req, $resp) if ($prefs->{"debug"});
    return($resp->code < 400);
}

sub get_with_credentials
{
    my $url = shift;
    my $req = HTTP::Request->new(GET => $prefs->{apiurl}.$url);
    $req->header("Authorization" => "Basic ".encode_base64($prefs->{username}.":".$prefs->{password}));
    my $resp = repeat($req);
    debuglog($req, $resp) if ($prefs->{"debug"});
    return($resp);
}

sub put
{
    my $url = shift;
    my $body = shift;
    return dummylog("PUT", $url, $body) if ($prefs->{dryrun});
    my $req = HTTP::Request->new(PUT => $prefs->{apiurl}.$url);
    $req->header("Content-type" => "text/xml");
    $req->header("Authorization" => "Basic ".encode_base64($prefs->{username}.":".$prefs->{password}));
    $req->content($body) if defined($body);
    my $resp = repeat($req);
    debuglog($req, $resp) if ($prefs->{"debug"});
    return $resp;
}

sub post
{
    my $url = shift;
    my $body = shift;
    return dummylog("POST", $url, $body) if ($prefs->{dryrun});
    my $req = HTTP::Request->new(POST => $prefs->{apiurl}.$url);
    $req->header("Authorization" => "Basic ".encode_base64($prefs->{username}.":".$prefs->{password}));
    $req->content($body) if defined($body); 
    # some not-proper-API-calls will expect HTTP form POST data;
    # try to determine magically whether we have an XML or form message.
    if (defined($body) && ($body !~ /^</))
    {
        $req->header("Content-type" => "application/x-www-form-urlencoded");
    }
    else
    {
        $req->header("Content-type" => "text/xml");
    }
    my $resp = repeat($req);
    debuglog($req, $resp) if ($prefs->{"debug"});
    return $resp;
}

# modified form of post method, that uses the web base URL
# and also automatically adds a potentially existing auth token
# to form post content.
sub post_web
{
    my $url = shift;
    my $body = shift;
    return dummylog("POST", $url, $body) if ($prefs->{dryrun});
    login() unless defined($cookie_jar);
    my $req = HTTP::Request->new(POST => $prefs->{weburl}.$url);
    if (defined($auth_token))
    {
        $body .= "&" if defined($body);
        $body .= "authenticity_token=".uri_escape($auth_token);
        undef $auth_token;
    }
    $req->content($body) if defined($body); 
    $req->header("Content-type" => "application/x-www-form-urlencoded");
    my $resp = repeat($req);
    debuglog($req, $resp) if ($prefs->{"debug"});
    return $resp;
}

sub delete
{
    my $url = shift;
    my $body = shift;
    return dummylog("DELETE", $url, $body) if ($prefs->{dryrun});
    my $req = HTTP::Request->new(DELETE => $prefs->{apiurl}.$url);
    $req->header("Authorization" => "Basic ".encode_base64($prefs->{username}.":".$prefs->{password}));
    $req->header("Content-type" => "text/xml");
    $req->content($body) if defined($body);
    my $resp = repeat($req);
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
    print STDERR "Request:\n".$request->content()."\n" if ($prefs->{"debug_request_body"});
    print STDERR "Response:\n".$response->content()."\n" if ($prefs->{"debug_response_body"});
}

sub dummylog
{
    my ($method, $url, $body) = @_;
    print STDERR "$method $url\n";
    print STDERR "$body\n\n";
    return $dummy;
}
sub set_timeout
{
    my $to = shift;
    $ua->timeout($to);
}

1;
