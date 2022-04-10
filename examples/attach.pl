#!/usr/bin/env perl

use 5.016;
use utf8;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Getopt::Long::Descriptive;
use JIRACLI qw/get_credentials/;

my ($opt, $usage) = describe_options(
    '%c %o FILE ...',
    ['jiraurl=s', "JIRA server base URL", {required => 1}],
    ['issue=s',   "Key of the issue to attach to", {required => 1}],
    ['help|h',    "Print usage message and exit"],
    {show_defaults => 1},
);

unless (@ARGV) {
    $usage->die({pre_text => "Missing FILE arguments.\n\n"});
}

if ($opt->help) {
    print $usage->text;
    exit 0;
}

my $jira = JIRA::REST->new(
    $opt->jiraurl,
    get_credentials(),
);

$jira->attach_files($opt->issue, @ARGV);


__END__
=encoding utf8

=head1 NAME

attachment.pl - Attach files to an issue

=head1 SYNOPSIS

  attach.pl [-ghir] [long options...] FILE ...
    --jiraurl STR JIRA server base URL
    --issue STR   Key of the issue to progress
    -h --help     Print usage message and exit

=head1 DESCRIPTION

This script attaches one of more files to a JIRA issue. The files are passed as
arguments.

=head1 OPTIONS

Common options are specified in the L<JIRACLI> documentation. Specific
options are defined below:

=over

=item * B<--issue STR>

Specifies the issue by its key (e.g. HD-1234).

=back

=head1 ENVIRONMENT

See the L<JIRACLI> documentation.

=head1 COPYRIGHT

Copyright 2022 CPQD.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Gustavo Chaves <gustavo@cpqd.com.br>
