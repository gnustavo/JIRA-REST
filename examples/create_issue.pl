#!/usr/bin/env perl

use 5.010;
use utf8;
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Getopt::Long::Descriptive;
use JIRACLI qw/get_credentials/;

my ($opt, $usage) = describe_options(
    '%c %o',
    ['jiraurl=s',   "JIRA server base URL", {default => 'https://jira.cpqd.com.br'}],
    ['project|p=s',  "Project to create issue under", {required => 1}],
    ['summary|s=s',  "Issue summary", {required => 1}],
    ['description|d=s',  "Issue description", {required => 1}],
    ['help|h',      "Print usage message and exit"],
    {show_defaults => 1},
);

if ($opt->help) {
    print $usage->text;
    exit 0;
}

my $jira = JIRA::REST->new(
    $opt->jiraurl,
    get_credentials(),
);

my $data = {
    fields => {
        project => {
            key => $opt->project
        },
        summary => $opt->summary,
        description => $opt->description,
        issuetype => {
          name => 'Bug'
        }
    }
};

my $res = $jira->POST('/issue', undef, $data);

print "Issue created ID: $res->{id}\n";

__END__
=encoding utf8

=head1 NAME

create_issue.pl - Creates an issue

=head1 SYNOPSIS

  create_issue.pl [-hn] [long options...]
    --jiraurl STR   JIRA server base URL
                    (default value: https://jira.cpqd.com.br)
    --project STR   The project key
    --summary STR   Issue Summary
    --description   Issue Description
    -h --help       Print usage message and exit

=head1 DESCRIPTION

This script creates an issue

=back

=head1 ENVIRONMENT

See the L<JIRACLI> documentation.

=head1 COPYRIGHT

Copyright 2016 CPqD.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Lisa Hare <lharey@gmail.com>