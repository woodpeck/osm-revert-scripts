#!/usr/bin/perl

# Adapter script for Note.pm module
# exports Note.pm functionality for command line use.

use strict;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long;
use Note;
use XML::Twig;
use utf8;
binmode STDOUT;

if ($ARGV[0] eq "comment")
{
    my $text;
    my $correct_options = GetOptions(
        "text=s" => \$text,
    );
    if ($correct_options && (scalar(@ARGV) == 2))
    {
        my $r = Note::comment($ARGV[1], $text);
        print "note commented: $r\n" if defined($r);
        exit;
    }
}

if (($ARGV[0] eq "hide") && (scalar(@ARGV) == 2))
{
    my $r = Note::hide($ARGV[1]);
    print "note hidden: $r\n" if defined($r);
    exit;
}

if (($ARGV[0] eq "reopen") && (scalar(@ARGV) == 2))
{
    my $r = Note::reopen($ARGV[1]);
    print "note reopened: $r\n" if defined($r);
    exit;
}

if (($ARGV[0] eq "get") && (scalar(@ARGV) == 2))
{
    my $raw = Note::get($ARGV[1]);
    print $raw;
    exit;
}

if (($ARGV[0] eq "reset") && (scalar(@ARGV) == 2))
{
    my $t = XML::Twig->new(keep_encoding => 1);
    my $raw = Note::get($ARGV[1]);
    exit unless defined($raw);
    $t->parse($raw);
    my ($id, $user, $text, $date, $lon, $lat);
    my $note = $t->root->first_child('note');

    if ($note->field('status') != 'open')
    {
        print "note is not open\n";
    }

    my $lon=$note->{'att'}->{'lon'};
    my $lat=$note->{'att'}->{'lat'};
    my $id=$note->field('id');
    my @comments = $note->first_child('comments')->children('comment');
    my $text = "(This note has been re-created from old note #$id)\n";
    my $an = 0;
    my $removed = 0;
    foreach my $comment(@comments)
    {
        my $msg = $comment->field('text');
        my $user = $comment->field('user');
        my $date = $comment->field('date');
        my $action = $comment->field('action');
        if (($action eq 'commented') && (!defined($user) || ($user eq "")))
        {
           $text .= "--------------------------\n(anonymous comment removed)\n" unless $an;
           $an = 1;
           $removed++;
        }
        else
        {
           $user = "anonymous user" if (!defined($user) || ($user eq ""));
           $text .= "--------------------------\n$user on $date:\n$msg\n";
           $an = 0;
        }
    }
    if (!defined($lat) || !defined($lon) || !defined($id))
    {
        print "cannot load note\n";
        exit;
    };

    if ($removed == 0)
    {
        print "no anonymous comments\n";
        exit;
    }

    my $r = Note::create($lat, $lon, $text);
    if (defined($r))
    {
        $t->parse($raw);
        my $id = $t->root->first_child('note')->field('id');;
        print "new note created: $id\n";
        $r = Note::hide($ARGV[1]);
        if (defined($r))
        {
            print "old note hidden\n";
        }
        else
        {
            print "cannot hide old note\n";
        }
    }
    else
    {
        print "cannot create new note: $r\n";
    }
    exit;
}

print <<EOF;
Usage: 
  $0 get <id>                load and print note XML
  $0 comment <id> <options>  add comment to the note
  $0 hide <id>               hide note
  $0 reopen <id>             reopen note
  $0 reset <id>              hide note, and create a new one with the first comment

options:
  --text <comment>
EOF
