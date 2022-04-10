#!/usr/bin/env perl

# perl -Ilib examples/search.pl --jiraurl https://lharey.atlassian.net --jql "assignee = 'Lisa Hare'"

use 5.016;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Getopt::Long::Descriptive;
use JIRACLI qw/get_credentials/;

my ($opt, $usage) = describe_options(
    '%c %o',
    ['jiraurl=s',   "JIRA server base URL", {required => 1}],
    ['jql=s',  "JQL query expression", {required => 1}],
    ['help|h',      "Print usage message and exit"],
    {show_defaults => 1},
);

if ($opt->help) {
    print $usage->text;
    exit 0;
}

my ($username, $password) = get_credentials();

# Scripts which make lots of calls to Jira should set up a session to be gentle.
my $jira = JIRA::REST->new({
    url => $opt->jiraurl,
    username => $username,
    password => $password,
    session => 1,
});

$jira->set_search_iterator({
    jql    => $opt->jql,
    fields => [qw/summary issuetype status priority assignee reporter/],
});

while (my $issue = $jira->next_issue) {
    my $fields = $issue->{fields};
    print <<"EOS";
ID: $issue->{id}
Summary: $fields->{summary}
Type: $fields->{issuetype}{name}
Status: $fields->{status}{name}
Priority: $fields->{priority}{name}
Reporter: $fields->{reporter}{name}

EOS
}


__END__

=head1 NAME

search.pl - Search JIRA issues by a JQL filter

=head1 SYNOPSIS

  search.pl [-hn] [long options...]
    --jiraurl STR   JIRA server base URL
    --jql STR       JQL query expression
    -h --help       Print usage message and exit

=head1 DESCRIPTION

This script searches JIRA issues by a JQL filter, printing their keys on
STDOUT, one per line, or more information about them, depending on the
options given.

=head1 OPTIONS

=over

=item * B<--jql STR>

Specifies the L<JQL
expression|https://confluence.atlassian.com/jirasoftwareserver072/advanced-searching-829057400.html>
used to search for issues.

=item * B<--jiraurl STR>

The JIRA server base url

=back

=head1 ENVIRONMENT

See the L<JIRACLI> documentation.

=head1 COPYRIGHT

Copyright 2016-2022 CPQD.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Gustavo Chaves <gustavo@cpqd.com.br>
Lisa Hare <lharey@gmail.com>
