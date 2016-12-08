# -*- cperl -*-

use strict;
use warnings;
use lib 't';
use Test::More tests => 5;
use JIRA::REST;

my $jira = new_ok('JIRA::REST', [{ url => 'https://jira.atlassian.com', anonymous => 1 }]);

BAIL_OUT('Cannot proceed because I could not create a JIRA::REST object') unless $jira;

my $project = eval {$jira->GET('/project/JRA')};

ok(defined $project && $project->{key} eq 'JRA', 'GET /project/JRA');

my $validate = eval {$jira->GET('/projectvalidate/key', {key => 'JRA'})};

ok(defined $validate && exists $validate->{errors}{projectKey}, 'GET /projectvalidate/key');

my $info = eval {$jira->GET('/serverInfo')};

ok(defined $info && $info->{serverTitle} eq 'Atlassian JIRA', 'GET /serverInfo');

$jira->set_search_iterator({
    jql        => 'project = JRA AND resolution IS EMPTY AND issuetype = Bug ORDER BY key DESC',
    fields     => [qw/description/],
    maxResults => 10,
});

my $issue = eval {$jira->next_issue};

ok(defined $issue && ref $issue && exists $issue->{fields}{description}, 'JQL search');
