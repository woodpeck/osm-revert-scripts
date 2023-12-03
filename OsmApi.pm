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
use Module::Load::Conditional qw[can_load];
use LWP::UserAgent;
use MIME::Base64 qw(encode_base64 encode_base64url);
use HTTP::Cookies;
use URI::Escape;
use Digest::SHA qw(sha256);

our $prefs_path;
our $prefs;
our $prefs_eol = 1;
our $ua;
our $agent;
our $dummy;
our $noversion;
our $cookie_jar;
our $auth_token;
our $oauth2_client_ids = {
    "api06.dev.openstreetmap.org:443" => "FEGTbR13GBJ8o3Z1FJLFUqcgMYrvmwzEbN2mciMz528",
    "master.apis.dev.openstreetmap.org:443" => "FEGTbR13GBJ8o3Z1FJLFUqcgMYrvmwzEbN2mciMz528",
    "www.openstreetmap.org:443" => "j2hkpmK8D3XRgXqU-X0fyaIZsehbTUdfZDE4eg-7JJA",
    "api.openstreetmap.org:443" => "j2hkpmK8D3XRgXqU-X0fyaIZsehbTUdfZDE4eg-7JJA",
    "www.openhistoricalmap.org:443" => "JH6N562wvXBEEntUsYIhXVcfiizLSQvU6Hgw7nVIkVg"
};
our $translated_weburls = {
    "https://api.openstreetmap.org/" => "https://www.openstreetmap.org/"
};

INIT
{
    if (can_load(modules => {'File::HomeDir' => undef}))
    {
        $prefs_path = File::HomeDir::home()."/.osmtoolsrc";
    }
    else
    {
        $prefs_path = $ENV{HOME}."/.osmtoolsrc";
    }

    $prefs = { "dryrun" => 1 };

    open (PREFS, $prefs_path) or die "cannot open $prefs_path";
    while(<PREFS>)
    {
        if (/^([^=]*)=(.*)/)
        {
            $prefs->{$1} = $2;
        }
        $prefs_eol = substr ($_, -1) eq "\n";
    }
    close (PREFS);
    
    # override user name and password from environment if given
    $prefs->{username} = $ENV{OSMTOOLS_USERNAME} if (defined($ENV{OSMTOOLS_USERNAME}));
    $prefs->{password} = $ENV{OSMTOOLS_PASSWORD} if (defined($ENV{OSMTOOLS_PASSWORD}));
    
    foreach my $required("apiurl")
    {
        die "$prefs_path does not have $required" unless defined($prefs->{$required});
    }

    if (!defined($prefs->{instance}))
    {
        $prefs->{instance} = sprintf "%010x", $$ * rand(100000000);
        append_pref("instance");
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
    $agent = "osmtools/$revno ($^O, ".$prefs->{instance}.")";
    $ua->agent($agent);
    $ua->timeout(600);
    push @{$ua->requests_redirectable}, 'POST';
    push @{$ua->requests_redirectable}, 'PUT';

    $prefs->{debug} = $prefs->{dryrun} unless (defined($prefs->{debug}));

    $dummy = HTTP::Response->new(200);

    my $weburl = $prefs->{'apiurl'};
    if ($weburl =~ /(.*\/)api\/0.6\//)
    {
        $weburl = $1;
    }
    if (defined($translated_weburls->{$weburl}))
    {
        $weburl = $translated_weburls->{$weburl};
    }
    $prefs->{'weburl'} = $weburl;

    if (!defined($prefs->{oauth2_client_id}) && defined($oauth2_client_ids->{$host}))
    {
        $prefs->{oauth2_client_id} = $oauth2_client_ids->{$host};
    }
}

# API subs
# --------

sub get
{
    my $url = shift;
    my $body = shift;
    my $privileged = shift;
    my $req = HTTP::Request->new(GET => $prefs->{apiurl}.$url);
    return run_api_request($req, $privileged);
}

sub exists
{
    my $url = shift;
    my $body = shift;
    my $privileged = shift;
    my $req = HTTP::Request->new(HEAD => $prefs->{apiurl}.$url);
    my $resp = run_api_request($req, $privileged);
    return($resp->code < 400);
}

sub put
{
    my $url = shift;
    my $body = shift;
    my $privileged = shift;
    return dummylog("PUT", $url, $body) if ($prefs->{dryrun});
    my $req = HTTP::Request->new(PUT => $prefs->{apiurl}.$url);
    $req->header("Content-type" => "text/xml");
    $req->content($body) if defined($body);
    return run_api_request($req, $privileged);
}

sub post
{
    my $url = shift;
    my $body = shift;
    my $privileged = shift;
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
    return run_api_request($req, $privileged);
}

sub post_multipart
{
    use HTTP::Request::Common;

    my $url = shift;
    my $req = HTTP::Request::Common::POST($prefs->{apiurl}.$url, @_, 'Content_Type' => 'form-data');
    return run_api_request($req);
}

sub delete
{
    my $url = shift;
    my $body = shift;
    my $privileged = shift;
    return dummylog("DELETE", $url, $body) if ($prefs->{dryrun});
    my $req = HTTP::Request->new(DELETE => $prefs->{apiurl}.$url);
    $req->header("Content-type" => "text/xml");
    $req->content($body) if defined($body);
    return run_api_request($req, $privileged);
}

# Web subs
# --------

sub login
{
    require_username_and_password();
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
    $auth_token = $1 if ($resp->content =~ /<meta name="csrf-token" content="(.*)" \/>/);
    debuglog($req, $resp) if ($prefs->{"debug"});
    return $resp;
}

# Utility subs
# ------------

sub weburl
{
    my $path = shift || '';
    return $prefs->{'weburl'} . $path;
}

sub append_pref
{
    my $pref_name = shift;
    open(PREFS, ">>$prefs_path");
    printf PREFS "\n" unless $prefs_eol;
    printf PREFS "$pref_name=".$prefs->{$pref_name};
    close(PREFS);
    $prefs_eol = 0;
}

sub run_api_request
{
    my $req = shift;
    my $privileged = shift;
    add_credentials($req, $privileged);
    my $resp = repeat($req);
    debuglog($req, $resp) if ($prefs->{"debug"});
    return $resp;
}

sub add_credentials
{
    my $req = shift;
    my $privileged = shift;
    if (defined($prefs->{oauth2_client_id}) && $prefs->{oauth2_client_id})
    {
        my $token = read_existing_oauth2_token($privileged);
        if (!$token)
        {
            $token = request_oauth2_token("oauth2_token");
        }
        $req->header("Authorization" => "Bearer $token");
    }
    else
    {
        require_username_and_password($privileged);
        $req->header("Authorization" => "Basic ".encode_base64($prefs->{username}.":".$prefs->{password}));
    }
}

sub require_username_and_password
{
    if (can_load(modules => {'Term::ReadKey' => undef}, autoload => 1))
    {
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
            # read user name from terminal if not set
            print 'User name: ';
            $prefs->{username} = $1 if (ReadLine(0) =~ /^(.*)\n$/);
            print "\n";
        }

        unless (defined($prefs->{password}))
        {
            # read password from terminal if not set
            print 'Password: ';
            ReadMode('noecho');
            $prefs->{password} = $1 if (ReadLine(0) =~ /^(.*)\n$/);
            ReadMode('restore');
            print "\n";
        }
    }

    foreach my $required("username","password")
    {
        die "$prefs_path does not have $required" unless defined($prefs->{$required});
    }
}

sub read_existing_oauth2_token
{
    my $privileged = shift;
    if (!$privileged && defined($prefs->{"oauth2_token_secondary"}))
    {
        return $prefs->{"oauth2_token_secondary"};
    }
    if (defined($prefs->{"oauth2_token"}))
    {
        return $prefs->{"oauth2_token"};
    }
    return undef;
}

sub introspect_existing_oauth2_token
{
    my $privileged = shift;
    my $req = HTTP::Request->new(POST => $prefs->{weburl}."oauth2/introspect");
    $req->content(
        "client_id=" . uri_escape($prefs->{oauth2_client_id}) .
        "&token=" . uri_escape(read_existing_oauth2_token($privileged)));
    $req->header("Content-type" => "application/x-www-form-urlencoded");
    $req->header("Content-length" => length($req->content));
    my $resp = $ua->request($req);
    debuglog($req, $resp) if ($prefs->{"debug"});
    return $resp;
}

sub check_oauth2_token
{
    my $token_name = shift;
    return defined($prefs->{$token_name});
}

sub request_oauth2_token
{
    die "oauth2 token request requires typing/pasting a code, but STDIN is busy with piped input\ntry running 'tokens.pl request' first to get oauth2 tokens" unless -t STDIN;
    die "Requesting oauth2 tokens requires 'oauth2_client_id' to be set in .osmtoolsrc for custom 'apiurl'." unless (defined($prefs->{oauth2_client_id}) && $prefs->{oauth2_client_id});

    my ($token_name, $scope) = @_;
    $scope = "read_prefs write_api write_notes read_gpx write_gpx" unless defined($scope);

    my $code_verifier_bytes;
    if (can_load(modules => {'Bytes::Random::Secure' => undef}))
    {
        $code_verifier_bytes = Bytes::Random::Secure::random_bytes(48);
    }
    else
    {
        $code_verifier_bytes = join "", map({ chr(int(rand() * 256)) } 1..48);
        print "WARNING: Using unsecure random number generator to generate PKCE code verifier, consider installing Bytes::Random::Secure module\n";
    }

    my $redirect_uri = "urn:ietf:wg:oauth:2.0:oob";
    my $code_verifier = encode_base64url $code_verifier_bytes;
    my $code_challenge = encode_base64url sha256($code_verifier);
    my $request_code_url = "$prefs->{weburl}oauth2/authorize?" .
        "client_id=" . uri_escape($prefs->{oauth2_client_id}) .
        "&redirect_uri=" . uri_escape($redirect_uri) .
        "&scope=" . uri_escape($scope) .
        "&response_type=code" .
        "&code_challenge=" . uri_escape($code_challenge) .
        "&code_challenge_method=S256";
    print "Open the following url:\n$request_code_url\n\n";

    print "Copy the code here: ";
    my $code;
    while ($code = <STDIN>)
    {
        chomp $code;
        last if $code ne "";
    }
    my $req = HTTP::Request->new(POST => $prefs->{weburl}."oauth2/token");
    $req->content(
        "client_id=" . uri_escape($prefs->{oauth2_client_id}) .
        "&redirect_uri=" . uri_escape($redirect_uri) .
        "&grant_type=authorization_code" .
        "&code=" . uri_escape($code) .
        "&code_verifier=" . uri_escape($code_verifier));
    $req->header("Content-type" => "application/x-www-form-urlencoded");
    $req->header("Content-length" => length($req->content));
    my $resp = $ua->request($req);
    debuglog($req, $resp) if ($prefs->{"debug"});
    die "no token in code exchange response" unless($resp->content =~ /"access_token":"([^"]+)"/);
    my $token = $1;
    $prefs->{$token_name} = $token;
    append_pref($token_name);
    return $token;
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
