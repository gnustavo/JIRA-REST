#!/usr/bin/env perl

use 5.010;
use utf8;
use strict;
use autodie;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Getopt::Long::Descriptive;
use JIRACLI qw/get_credentials/;

my ($opt, $usage) = describe_options(
    '%c %o',
    ['jiraurl=s',   "JIRA server base URL", {default => 'https://jira.cpqd.com.br'}],
    ['issue|i=s',         "Key of the issue to progress", {required => 1}],
    ['transition-id|t=i', "ID of the transition to make", {required => 1}],
    ['resolution|r=s', "Resolution name to set"],
    ['comment|c=s',    "Comment string to insert during transition"],
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
    transition => { id => $opt->transition_id },
};

$data->{fields}{resolution} = { name => $opt->resolution } if $opt->resolution;
$data->{update}{comment}    = [{ add => { body => $opt->comment }}] if $opt->comment;

$jira->POST("/issue/@{[$opt->issue]}/transitions", undef, $data);


__END__
=encoding utf8

=head1 NAME

transition.pl - Make a transition in a JIRA issue

=head1 SYNOPSIS

  transition.pl [-hn] [long options...]
    --jiraurl STR         JIRA server base URL
                          (default value: https://jira.cpqd.com.br)
    --issue STR           Key of the issue to progress
    --transition-id INT   ID of the transition to make
    --resolution STR      Resolution name to set
    --comment STR         Comment string to insert during transition
    -n --dont             Do not change anything
    -h --help             Print usage message and exit

=head1 DESCRIPTION

This script makes a JIRA issue transition through its workflow.

=head1 OPTIONS

Common options are specified in the L<JIRACLI> documentation. Specific
options are defined below:

=over

=item * B<--issue STR>

Specifies the issue by its key (e.g. HD-1234).

=item * B<--transition-id INT>

Specifies the transition that should be performed by its numeric ID. You can
grok it by hovering the mouse over the transition button and looking for the
C<action=N> part in its URL.

=item * B<--resolution STR>

If the transition leads to a terminal state you can specify a Resolution to
be set.

=item * B<--comment STR>

Specifies a comment to be added to the issue during the transition. Note
that the comment will not be added if the transition doesn't have a screen
associated with it.

=back

=head1 ENVIRONMENT

See the L<JIRACLI> documentation.

=head1 COPYRIGHT

Copyright 2016 CPQD.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Gustavo Chaves <gustavo@cpqd.com.br>
Lisa Hare <lharey@gmail.com>
