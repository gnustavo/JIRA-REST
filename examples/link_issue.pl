#!/usr/bin/env perl

use 5.016;
use utf8;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Getopt::Long::Descriptive;
use JIRACLI qw/get_credentials/;

my ($opt, $usage) = describe_options(
    '%c %o',
    ['jiraurl=s',   "JIRA server base URL", {required => 1}],
    ['issue|i=s',   "Key of the issue to progress", {required => 1}],
    ['url|u=s',     "URL of the link", {required => 1}],
    ['title|t=s',   "Title of the link", {required => 1}],
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

my $link = {
    object => {
        url   => $opt->url,  # eg. 'https://example.com/'
        title => $opt->title # eg. 'Link to the website'
    }
}; # See https://developer.atlassian.com/server/jira/platform/jira-rest-api-for-remote-issue-links/

$jira->POST("/issue/@{[$opt->issue]}/remotelink", undef, $link);


__END__
=encoding utf8

=head1 NAME

link_issue.pl - Link a JIRA issue

=head1 SYNOPSIS

  link_issue.pl [-ghir] [long options...]
    --jiraurl STR        JIRA server base URL
    -i STR --issue STR   Key of the issue to progress
    -u STR --url   STR   URL of the link
    -t STR --title STR   Title of the link
    -h --help            Print usage message and exit

=head1 DESCRIPTION

This script adds a link to a JIRA issue.

=head1 OPTIONS

Common options are specified in the L<JIRACLI> documentation. Specific
options are defined below:

=over

=item * B<--issue STR>

Specifies the issue by its key (e.g. HD-1234).

=item * B<--url STR>

URL of the link.

=item * B<--title STR>

Title of the link.

=back

=head1 ENVIRONMENT

See the L<JIRACLI> documentation.

=head1 COPYRIGHT

Copyright 2019-2024 CPQD.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Elvin Aslanov <rwp.primary@gmail.com>
