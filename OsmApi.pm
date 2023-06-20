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
use File::HomeDir;

our $prefs;
our $ua;
our $dummy;
our $noversion;
our $cookie_jar;
our $auth_token;

BEGIN
{
    my $prefs_filename = home()."/.osmtoolsrc";
    my $prefs_eol;

    sub read_prefs_file {
        $prefs = { "dryrun" => 1 };
        $prefs_eol = 1;

        open (PREFS, $prefs_filename) or die "cannot open $prefs_filename";
        while(<PREFS>)
        {
            if (/^([^=]*)=(.*)/)
            {
                $prefs->{$1} = $2;
            }
            $prefs_eol = substr ($_, -1) eq "\n";
        }
        close (PREFS);
    }

    read_prefs_file;
    if ($prefs->{local}) {
        $prefs_filename = "./.osmtoolsrc";
        read_prefs_file;
    }

    # override user name and password from environment if given
    $prefs->{username} = $ENV{OSMTOOLS_USERNAME} if (defined($ENV{OSMTOOLS_USERNAME}));
    $prefs->{password} = $ENV{OSMTOOLS_PASSWORD} if (defined($ENV{OSMTOOLS_PASSWORD}));
    
    foreach my $required("apiurl")
    {
        die "$prefs_filename does not have $required" unless defined($prefs->{$required});
    }

    if (!defined($prefs->{instance}))
    {
        $prefs->{instance} = sprintf "%010x", $$ * rand(100000000);
        open(PREFS, ">>$prefs_filename");
        printf PREFS "\n" unless $prefs_eol;
        printf PREFS "instance=".$prefs->{instance};
        close(PREFS);
    }

    $prefs->{apiurl} =~ m!(https?)://([^/]+)/!;
    my $protocol = $1;
    my $host = $2;
    if ($host !~ /:/)
    {
        $host .= sprintf ":%d", ($protocol eq "https") ? 443 : 80;
    }
    $ua = LWP::UserAgent->new;
    my $revision = '$Revision: 30253 $';
    my $revno = 0;
    $revno = $1 if ($revision =~ /:\s*(\d+)/);
    $ua->agent("osmtools/$revno ($^O, ".$prefs->{instance}.")");
    $ua->timeout(600);
    push @{$ua->requests_redirectable}, 'POST';
    push @{$ua->requests_redirectable}, 'PUT';

    $prefs->{debug} = $prefs->{dryrun} unless (defined($prefs->{debug}));

    $dummy = HTTP::Response->new(200);

    $prefs->{'weburl'} = $prefs->{'apiurl'};
    if ($prefs->{'weburl'} =~ /(.*\/)api\/0.6\//)
    {
        $prefs->{'weburl'} = $1;
    }

    print STDERR "Read config from $prefs_filename\n" if ($prefs->{debug});
}

sub require_username_and_password
{
    # read user name from terminal if not set
    if (defined($prefs->{username}))
    {
        # only print user name if we're about to read password interactively
        unless (defined($prefs->{password}))
        {
            print 'User name: ' . $prefs->{username} . "\n"
        }
    }
    else
    {
        use Term::ReadKey;
        print 'User name: ';
        $prefs->{username} = $1 if (ReadLine(0) =~ /^(.*)\n$/);
        print "\n";
    }
    
    # read password from terminal if not set
    unless (defined($prefs->{password}))
    {
        use Term::ReadKey;
        print 'Password: ';
        ReadMode('noecho');
        $prefs->{password} = $1 if (ReadLine(0) =~ /^(.*)\n$/);
        ReadMode('restore');
        print "\n";
    }

    foreach my $required("username","password")
    {
        die home()."/.osmtoolsrc does not have $required" unless defined($prefs->{$required});
    }
}

sub add_credentials
{
    require_username_and_password;
    my $req = shift;
    $req->header("Authorization" => "Basic ".encode_base64($prefs->{username}.":".$prefs->{password}));
}

sub login
{
    require_username_and_password;
    $ua->cookie_jar($cookie_jar = HTTP::Cookies->new());
    my $req = HTTP::Request->new(GET => $prefs->{weburl}."login");
    my $resp = $ua->request($req);
    debuglog($req, $resp) if ($prefs->{"debug"});
    die unless($resp->is_success);
    my $cont = $resp->content;
    die unless($cont =~ /<meta name="csrf-token" content="(.*)" \/>/);
    $auth_token = $1;
    $req = HTTP::Request->new(POST => $prefs->{weburl}."login");
    $req->content(
        "authenticity_token=" . uri_escape($auth_token) .
        "&referer=%2F".
        "&openid_url=".
        "&utf8=%E2%9C%93".
        "&commit=Login".
        "&username=". uri_escape($prefs->{'username'}).
        "&password=". uri_escape($prefs->{'password'}));
    $req->header("Content-type" => "application/x-www-form-urlencoded");
    $req->header("Content-length" => length($req->content));
    $resp = $ua->request($req);
    debuglog($req, $resp) if ($prefs->{"debug"});
    die unless($resp->content =~ /<head[^>]* data-user="(\d+)"/);
    print("logged in as user $1\n");
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
    add_credentials($req);
    my $resp = repeat($req);
    debuglog($req, $resp) if ($prefs->{"debug"});
    return($resp);
}

sub exists
{
    my $url = shift;
    my $req = HTTP::Request->new(HEAD => $prefs->{apiurl}.$url);
    add_credentials($req);
    my $resp = repeat($req);
    debuglog($req, $resp) if ($prefs->{"debug"});
    return($resp->code < 400);
}

sub get_with_credentials
{
    # get is now with credentials by default
    return get(@_);
}

sub put
{
    my $url = shift;
    my $body = shift;
    return dummylog("PUT", $url, $body) if ($prefs->{dryrun});
    my $req = HTTP::Request->new(PUT => $prefs->{apiurl}.$url);
    $req->header("Content-type" => "text/xml");
    $req->content($body) if defined($body);
    add_credentials($req);
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
    add_credentials($req);
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
    $req->header("Content-type" => "text/xml");
    $req->content($body) if defined($body);
    add_credentials($req);
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
    print STDERR "Request Headers:\n".$request->headers_as_string()."\n" if ($prefs->{"debug_request_headers"});
    print STDERR "Request:\n".$request->content()."\n" if ($prefs->{"debug_request_body"});
    print STDERR "Response Headers:\n".$response->headers_as_string()."\n" if ($prefs->{"debug_response_headers"});
    print STDERR "Response:\n".$response->content()."\n" if ($prefs->{"debug_response_body"});
}

sub dummylog
{
    my ($method, $url, $body) = @_;
    print STDERR "$method $url\n";
    print STDERR "$body\n\n" if defined($body);
    return $dummy;
}
sub set_timeout
{
    my $to = shift;
    $ua->timeout($to);
}

1;
