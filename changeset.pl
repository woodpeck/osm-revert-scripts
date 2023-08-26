#!/usr/bin/perl

# Adapter script for Changeset.pm module
# exports Changeset.pm functionality for command line use.

use strict;
use FindBin;
use lib $FindBin::Bin;
use List::Util qw(pairs pairgrep);
use Changeset;

my @regular_commands = (
    "create [<comment>]",     "create a changeset; returns ID created",
    "close <id> [<comment>]", "close a changeset and optionally set comment",
    "upload <id> <content>",  "upload changes to an open changeset",
    "comment <id> <comment>", "comment on an existing changeset",
);

if ($ARGV[0] eq "create")
{
    my $cs = Changeset::create($ARGV[1]);
    print "changeset created: $cs\n" if defined($cs);
    exit;
}

if ($ARGV[0] eq "close")
{
    if (!defined($ARGV[2]) || Changeset::update($ARGV[1], $ARGV[2]))
    {
        if (Changeset::close($ARGV[1]))
        {
            print "changeset closed.\n";
        }
    }
    exit;
}

if (($ARGV[0] eq "upload") && (scalar(@ARGV)==2))
{
    my $body = "";
    while(<STDIN>) { $body .= $_; }
    if (length($body) == 0)
    {
        print "usage: $0 upload <id> < content-to-upload\n";
        exit;
    }
    if (Changeset::upload($ARGV[1], $body))
    {
        print "changeset uploaded.\n";
    }
    exit;
}

if (($ARGV[0] eq "comment") && (scalar(@ARGV)==3))
{
    if (Changeset::comment($ARGV[1], $ARGV[2]))
    {
        print "comment added.\n";
    }
    exit;
}

my @download_commands = (
    "download",                   "download and display an existing changeset",
    "download-versions",          "download and display element versions of a changeset",
    "download-previous",          "download and display previous elements of a changeset",
    "download-next",              "download and display next elements of a changeset",
    "download-previous-versions", "display previous versions of elements in a changeset",
    "download-next-versions",     "display next versions of elements in a changeset",
    "download-previous-summary",  "display a summary table of previous changesets",
    "download-next-summary",      "display a summary table of next changesets",
);

if ((pairgrep {$a eq $ARGV[0]} @download_commands) && (scalar(@ARGV)==2))
{
    my ($command, $cid) = @ARGV;
    my $content = Changeset::download($cid);
    die unless defined($content);
    if ($command eq "download")
    {
        print $content;
        print "\n";
        exit;
    }
    
    my @element_versions = Changeset::get_element_versions($content);
    if ($command eq "download-versions") {
        print "$_\n" for @element_versions;
        exit;
    }

    exit unless $command =~ /^download-(previous|next)(.*)/;
    my $is_previous = $1 eq "previous";
    my $subcommand = $2;
    exit if download_siblings($subcommand, $cid, $is_previous, @element_versions);
}

my $command_width = 35;
print "Usage:\n";
foreach my $pair (pairs @regular_commands)
{
    printf "  %s %-35s %s\n", $0, $pair->key, $pair->value;
}
foreach my $pair (pairs @download_commands)
{
    printf "  %s %-35s %s\n", $0, $pair->key . " <id>", $pair->value;
}

sub download_siblings($$$@)
{
    my $subcommand = shift;
    my $cid = shift;
    my $is_previous = shift;
    my @element_versions = @_;

    my @other_element_versions;
    if ($is_previous)
    {
        @other_element_versions = Changeset::get_previous_element_versions(@element_versions);
    }
    else
    {
        @other_element_versions = Changeset::get_next_element_versions(@element_versions);
    }

    if ($subcommand eq "-versions")
    {
        print "$_\n" for @other_element_versions;
        return 1;
    }

    my $other_content = Changeset::download_elements(@other_element_versions);
    if ($subcommand eq "")
    {
        print $other_content;
        return 1;
    }

    my $other_summary = Changeset::get_changeset_summary($other_content);
    if ($subcommand eq "-summary")
    {
        print "# summary of changesets " . ($is_previous ? "preceding" : "following") . " $cid\n";
        print "# count, changeset, uid, user\n";
        print $other_summary;
        return 1;
    }
}
