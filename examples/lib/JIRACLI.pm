#!/usr/bin/env perl

package JIRACLI;

use 5.016;
use utf8;
use warnings;
use JIRA::REST;
use IO::Interactive qw(is_interactive);
use IO::Prompter;
use Carp;

use parent qw(Exporter);
our @EXPORT_OK = qw(get_credentials);
our $VERSION = '0.02';

sub get_credentials {
    my ($user, $pass) = @ENV{qw/jirauser jirapass/};

    return ($user, $pass) if defined $user && defined $pass;

    unless (is_interactive()) {
        # We cannot prompt the user if we're not talking to a
        # terminal.
        croak "Cannot prompt user for credentials because STDIN isn't a terminal.\n";
    }

    if (!defined $user) {
        $user = prompt(
            -prompt  => "Username:",
            -in      => \*STDIN,
            -out     => \*STDERR,
            -verbatim,
        );
    }

    if (! defined $pass) {
        $pass = prompt(
            -prompt  => "Password:",
            -in      => \*STDIN,
            -out     => \*STDERR,
            -echo    => '*',
            -verbatim,
        );
    }

    return ($user, $pass);
}

1;
__END__
=encoding utf8

=head1 NAME

JIRACLI - Common utilities for all JIRA CLI examples

=head1 SYNOPSIS

  use lib $FindBin::Bin;
  use JIRACLI;

=head1 DESCRIPTION

This module contains a few functions used by most of the JIRA CLI examples

=head1 FUNCTIONS

=head2 get_credentials

   my ($user, $pass) = get_credentials();

This function will first check for user and password specified in the
environment variables jirauser and jirpass.

If no environment variables set will prompt interactively for entry of user and password

=over

=head1 COPYRIGHT

Copyright 2016-2021 CPQD.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Gustavo Chaves <gustavo@cpqd.com.br>
