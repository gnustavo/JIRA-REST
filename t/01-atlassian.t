# -*- cperl -*-

use 5.016;
use warnings;
use lib 't';
use Test::More;
use JIRA::REST;

if ($ENV{RELEASE_TESTING}) {
    plan tests => 7;
} else {
    plan skip_all => 'these tests are for release testing';
}

my $jira = new_ok('JIRA::REST', [{ url => 'https://jira.atlassian.com', anonymous => 1 }]);

BAIL_OUT('Cannot proceed because I could not create a JIRA::REST object') unless $jira;

if (my $project = eval {$jira->GET('/rest/api/latest/project/JRASERVER')}) {
    ok(defined $project && $project->{key} eq 'JRASERVER', 'GET /rest/api/latest/project/JRASERVER');
} else {
    fail('GET /rest/api/latest/project/JRASERVER');
}

if (my $project = eval {$jira->GET('/project/JRASERVER')}) {
    ok(defined $project && $project->{key} eq 'JRASERVER', 'GET /project/JRASERVER');
} else {
    fail('GET /project/JRASERVER');
}

if (my $info = eval {$jira->GET('/serverInfo')}) {
    ok(defined $info && $info->{serverTitle} =~ /Atlassian/, 'GET /serverInfo');
} else {
    fail('GET /serverInfo');
}

$jira->set_search_iterator({
    jql        => 'project = JRASERVER AND resolution IS EMPTY AND issuetype = Bug ORDER BY key DESC',
    fields     => [qw/description/],
    maxResults => 10,
});

if (my $issue = eval {$jira->next_issue}) {
    ok(defined $issue && ref $issue && exists $issue->{fields}{description}, 'JQL search');
} else {
    fail('JQL search');
}

$jira = new_ok('JIRA::REST', [{ url => 'https://jira.atlassian.com/rest/api/latest', anonymous => 1 }]);

BAIL_OUT('Cannot proceed because I could not create a JIRA::REST object with a default API')
    unless $jira;

if (my $project = eval {$jira->GET('/project/JRASERVER')}) {
    ok(defined $project && $project->{key} eq 'JRASERVER', 'GET /project/JRASERVER (with set default API)');
} else {
    fail('GET /project/JRASERVER (with set default API)');
}

1;
