use strict;
use warnings;
use lib 't';
use Test::More;

my $module = 'JIRA::REST';

use_ok $module;

my $endpoints = [
    'https://example.com',
    'https://example.com/wiki/rest/api/latest',
    'https://example.com/wiki/rest/agile/latest',
    'https://example.com/rest/servicedeskapi/latest',
];

for my $endpoint (@$endpoints) {
    my $j = JIRA::REST->new( $endpoint, 'foo', 'bar' );
    ok ref $j eq $module, "$endpoint is valid";
}

done_testing;
