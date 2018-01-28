#!/usr/bin/env perl

use 5.010;
use utf8;
use strict;
use warnings;

package JIRACLI;

use JIRA::REST;

use vars qw($VERSION @ISA @EXPORT_OK);

require Exporter;

@ISA = qw(Exporter);
@EXPORT_OK = qw(get_credentials);
$VERSION = '0.01';

sub get_credentials {

    my ($user, $pass) = @ENV{'jirauser', 'jirapass'};

    return ($user, $pass) if defined $user && defined $pass;

    if (! -t STDIN) {
        die "Cannot prompt user for credentials because STDIN isn't a terminal. Please set environment variables jirauser and jirapass\n";
    }

    require Term::Prompt;
    Term::Prompt->import();

    if (!defined $user) {
        $user = prompt('x', "Enter Username: ", '', '');
    }

    if (! defined $pass) {
        $pass = prompt('p', "Enter Password: ", '', '');
        print "\n";
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

Copyright 2016 CPqD.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Gustavo Chaves <gustavo@cpqd.com.br>
