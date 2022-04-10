#!/usr/bin/env perl

use 5.016;
use utf8;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Getopt::Long::Descriptive;
# We need at least REST::Client version 280 to be able to download absolute URLs. See
# https://github.com/milescrawford/cpan-rest-client/commit/3cb20d8f8c42c3433a269abbaf437ad101a97563.
use REST::Client 280;
use JIRACLI qw/get_credentials/;

my ($opt, $usage) = describe_options(
    '%c %o [FILE]',
    ['jiraurl=s', "JIRA server base URL", {required => 1}],
    ['issue=s',   "Key of the issue from which to download attachments", {required => 1}],
    ['help|h',    "Print usage message and exit"],
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

my $issue = $jira->GET('/issue/' . $opt->issue);

# Get a reference to the attachment hashes
my $attachments = $issue->{fields}{attachment};

if (my $file = shift) {
    if (my ($attachment) = grep {$_->{filename} eq $file} @$attachments) {
        # The 'content' key of the attachment hash contains the complete URL to
        # the attachment. But we can't use the JIRA::REST::GET method to get it
        # because it expects a JSON response and not an octet-stream with the
        # attachment contents. So, we grok the underlying REST::Client from the
        # JIRA::REST object and use its methods to download the attachment,
        # which takes advantage of the already set up authentication mechanism.
        my $rest_client = $jira->rest_client;
        $rest_client->setContentFile($file);
        $rest_client->request(GET => $attachment->{content});
        $rest_client->setContentFile(undef);
    } else {
        die "No such attachment: $file\n";
    }
} else {
    if (my @attachments = map {$_->{filename}} @$attachments) {
        warn join("\n  ", 'Which attachment do you want to download?', sort @attachments), "\n";
    } else {
        warn "$opt->{issue} has no attachments\n";
    }
}


__END__
=encoding utf8

=head1 NAME

download_attachment.pl - Download an attachment from an issue

=head1 SYNOPSIS

  download_attachment.pl [-h] [long options...] [FILE]
    --jiraurl STR  JIRA server base URL
    --issue STR    Key of the issue from which to download attachments
    -h --help      Print usage message and exit

=head1 DESCRIPTION

This script downloads an attachment from a JIRA issue. If there is no FILE
argument the script lists the names of all the issue attachments. To download a
specific attachment, pass its name as the FILE argument. It is downloaded in the
current directory with the same name.

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
