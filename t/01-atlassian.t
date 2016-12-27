# -*- cperl -*-

use strict;
use warnings;
use lib 't';
use Test::More;
use JIRA::REST;

if ($ENV{RELEASE_TESTING}) {
    plan tests => 8;
} else {
    plan skip_all => 'these tests are for release testing';
}

my $jira = new_ok('JIRA::REST', [{ url => 'https://jira.atlassian.com', anonymous => 1 }]);

BAIL_OUT('Cannot proceed because I could not create a JIRA::REST object') unless $jira;

for my $project (eval {$jira->GET('/rest/api/latest/project/JRA')}) {
    ok(defined $project && $project->{key} eq 'JRA', 'GET /rest/api/latest/project/JRA');
};

for my $project (eval {$jira->GET('/project/JRA')}) {
    ok(defined $project && $project->{key} eq 'JRA', 'GET /project/JRA');
};

for my $validate (eval {$jira->GET('/projectvalidate/key', {key => 'JRA'})}) {
    ok(defined $validate && exists $validate->{errors}{projectKey}, 'GET /projectvalidate/key');
}

for my $info (eval {$jira->GET('/serverInfo')}) {
    ok(defined $info && $info->{serverTitle} eq 'Atlassian JIRA', 'GET /serverInfo');
}

$jira->set_search_iterator({
    jql        => 'project = JRA AND resolution IS EMPTY AND issuetype = Bug ORDER BY key DESC',
    fields     => [qw/description/],
    maxResults => 10,
});

for my $issue (eval {$jira->next_issue}) {
    ok(defined $issue && ref $issue && exists $issue->{fields}{description}, 'JQL search');
}

$jira = new_ok('JIRA::REST', [{ url => 'https://jira.atlassian.com/rest/api/latest', anonymous => 1 }]);

BAIL_OUT('Cannot proceed because I could not create a JIRA::REST object with a default API')
    unless $jira;

for my $project (eval {$jira->GET('/project/JRA')}) {
    ok(defined $project && $project->{key} eq 'JRA', 'GET /project/JRA (with set default API)');
};
