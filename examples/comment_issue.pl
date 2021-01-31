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
    ['jiraurl=s',   "JIRA server base URL", {default => 'https://jira.cpqd.com.br'}],
    ['issue|i=s',    "Key of the issue to progress", {required => 1}],
    ['comment|c=s', "Comment body", {required => 1}],
    ['visibility' => 'hidden' => {'one_of' => [
        ['group|g=s', "Group to restrict visibility to"],
        ['role|r=s',  "Role to restrict visibility to"],
    ]}],
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

my $comment = {body => $opt->comment};

if (my $type = $opt->visibility) {
    $comment->{visibility} = {
        type  => $type,
        value => $opt->$type,
    }
}

$jira->POST("/issue/@{[$opt->issue]}/comment", undef, $comment);

__END__
=encoding utf8

=head1 NAME

comment_issue.pl - Comment a JIRA issue

=head1 SYNOPSIS

  comment_issue.pl [-ghir] [long options...]
    --jiraurl STR        JIRA server base URL
                         (default value: https://jira.cpqd.com.br)
    -i STR --issue STR   Key of the issue to progress
    -c STR --comment STR Comment body
    -g STR --group STR   Group to restrict visibility to
    -r STR --role STR    Role to restrict visibility to
    -h --help            Print usage message and exit

=head1 DESCRIPTION

This script adds a comment to a JIRA issue.

=head1 OPTIONS

Common options are specified in the L<JIRACLI> documentation. Specific
options are defined below:

=over

=item * B<--issue STR>

Specifies the issue by its key (e.g. HD-1234).

=item * B<--comment STR>

The comment body.

=item * B<--group STR>

Use this option to restrict the comment visibility to the specified group.

=item * B<--role STR>

Use this option to restrict the comment visibility to the specified role.

Note that the B<--group> and B<--role> options are mutually exclusive.

=back

=head1 ENVIRONMENT

See the L<JIRACLI> documentation.

=head1 COPYRIGHT

Copyright 2019 CPQD.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Gustavo Chaves <gustavo@cpqd.com.br>
