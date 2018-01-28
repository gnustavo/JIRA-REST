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
    ['issue|i=s',    "Key of the issue to progress", {required => 1}],
    ['assign|a=s@',  "Set of KEY[.ATTR]=VALUE assignments to perform", { required => 1 }],
    ['nonotify',   "Supress email notification about the change."],
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

my %assignments;
foreach my $assign (@{$opt->assign}) {
    if (my ($key, $value) = ($assign =~ /(.+?)=(.+)/)) {
        if (my ($kkey, $attr) = ($key =~ /(.+?)\.(.+)/)) {
            if (!$assignments{$kkey}) {
                $assignments{$kkey} = {};
            }
            $assignments{$kkey}{$attr} = $value;
        } else {
            $assignments{$key} = $value;
        }
    } else {
        die "Invalid assignment specification: $assign";
    }
}

my $data = { fields => \%assignments };
$data->{notifyUsers} = 'false' if $opt->nonotify;

$jira->PUT("/issue/@{[$opt->issue]}", undef, $data);

__END__
=encoding utf8

=head1 NAME

edit_issue.pl - Edit a JIRA issue

=head1 SYNOPSIS

  edit.pl [-h] [long options...]
    --jiraurl STR     JIRA server base URL
                      (default value: https://jira.cpqd.com.br)
    --issue STR       Key of the issue to progress
    --assign STR...   Set of KEY[.ATTR]=VALUE assignments to perform
    --nonotify        Supress email notification about the change.
    -h --help         Print usage message and exit

=head1 DESCRIPTION

This script edits a JIRA issue, changing its fields.

=head1 OPTIONS

Common options are specified in the L<JIRACLI> documentation. Specific
options are defined below:

=over

=item * B<--issue STR>

Specifies the issue by its key (e.g. HD-1234).

=item * B<--assign STR...>

This multi-valued option specifies which fields are to be changed.

Numeric, date, or string fields can be specified like this:

  --assign="summary=New summary"
  --assign="duedate=2017-01-01"

Structured fields may need the name of an attribute to be assigned:

  --assign="assignee.name=gustavo"
  --assign="assignee.emailAddress=gustavo@cpqd.com.br"

=item * B<--nonotify>

By default JIRA sends email notifications to all parties involved in an
issue when it's changed. This option supresses those notifications. However,
admin or project admin permissions are required to disable the notification.

=back

=head1 ENVIRONMENT

See the L<JIRACLI> documentation.

=head1 COPYRIGHT

Copyright 2016 CPqD.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Gustavo Chaves <gustavo@cpqd.com.br>
Lisa Hare <lharey@gmail.com>
