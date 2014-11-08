package JIRA::REST;
# ABSTRACT: Thin wrapper around JIRA's REST API

use 5.010;
use utf8;
use strict;
use warnings;

use Carp;
use URI;
use MIME::Base64;
use URI::Escape;
use JSON;
use Data::Util qw/:check/;
use REST::Client;

sub new {
    my ($class, $URL, $username, $password, $rest_client_config) = @_;

    $URL = URI->new($URL) if is_string($URL);
    is_instance($URL, 'URI')
        or croak __PACKAGE__ . "::new: URL argument must be a string or a URI object.\n";

    # Choose the latest REST API unless already specified
    unless ($URL->path =~ m@/rest/api/(?:\d+|latest)/?$@) {
        $URL->path($URL->path . '/rest/api/latest');
    }

    # If no password is set we try to lookup the credentials in the .netrc file
    if (! defined $password) {
        eval {require Net::Netrc}
            or croak "Can't require Net::Netrc module. Please, specify the USERNAME and PASSWORD.\n";
        if (my $machine = Net::Netrc->lookup($URL->host, $username)) { # $username may be undef
            $username = $machine->login;
            $password = $machine->password;
        } else {
            croak "No credentials found in the .netrc file.\n";
        }
    }

    is_string($username)
        or croak __PACKAGE__ . "::new: USERNAME argument must be a string.\n";

    is_string($password)
        or croak __PACKAGE__ . "::new: PASSWORD argument must be a string.\n";

    $rest_client_config = {} unless defined $rest_client_config;
    is_hash_ref($rest_client_config)
        or croak __PACKAGE__ . "::new: REST_CLIENT_CONFIG argument must be a hash-ref.\n";

    my $rest = REST::Client->new($rest_client_config);

    # Set default base URL
    $rest->setHost($URL);

    # Follow redirects/authentication by default
    $rest->setFollow(1);

    # Since JIRA doesn't send an authentication chalenge, we may
    # simply force the sending of the authentication header.
    $rest->addHeader(Authorization => 'Basic ' . encode_base64("$username:$password"));

    # Configure UserAgent name
    $rest->getUseragent->agent(__PACKAGE__);

    return bless {
        rest => $rest,
        json => JSON->new->utf8->allow_nonref,
    } => $class;
}

sub _error {
    my ($self, $content, $type, $code) = @_;

    $type = 'text/plain' unless $type;
    $code = 500          unless $code;

    my $msg = __PACKAGE__ . " Error[$code";

    if (eval {require HTTP::Status}) {
        if (my $status = HTTP::Status::status_message($code)) {
            $msg .= " - $status";
        }
    }

    $msg .= "]:\n";

    if ($type =~ m:text/plain:i) {
        $msg .= $content;
    } elsif ($type =~ m:application/json:) {
        my $error = $self->{json}->decode($content);
        if (ref $error eq 'HASH') {
            # JIRA errors may be laid out in all sorts of ways. You have to
            # look them up from the scant documentation at
            # https://docs.atlassian.com/jira/REST/latest/.

            # /issue/bulk tucks the errors one level down, inside the
            # 'elementErrors' hash.
            $error = $error->{elementErrors} if exists $error->{elementErrors};

            # Some methods tuck the errors in the 'errorMessages' array.
            if (my $errorMessages = $error->{errorMessages}) {
                $msg .= "- $_\n" foreach @$errorMessages;
            }

            # And some tuck them in the 'errors' hash.
            if (my $errors = $error->{errors}) {
                $msg .= "- [$_] $errors->{$_}\n" foreach sort keys %$errors;
            }
        } else {
            $msg .= $content;
        }
    } elsif ($type =~ m:text/html:i && eval {require HTML::TreeBuilder}) {
        $msg .= HTML::TreeBuilder->new_from_content($content)->as_text;
    } elsif ($type =~ m:^text/:i) {
        $msg .= "<Content-Type: $type>$content</Content-Type>";
    } else {
        $msg .= "<Content-Type: $type>(binary content not shown)</Content-Type>";
    };
    $msg =~ s/\n*$/\n/s;       # end message with a single newline
    return $msg;
}

sub _content {
    my ($self) = @_;

    my $rest    = $self->{rest};
    my $code    = $rest->responseCode();
    my $type    = $rest->responseHeader('Content-Type');
    my $content = $rest->responseContent();

    $code =~ /^2/
        or croak $self->_error($content, $type, $code);

    return unless $content;

    if (! defined $type) {
        croak $self->_error("Cannot convert response content with no Content-Type specified.");
    } elsif ($type =~ m:^application/json:i) {
        return $self->{json}->decode($content);
    } elsif ($type =~ m:^text/plain:i) {
        return $content;
    } else {
        croak $self->_error("I don't understand content with Content-Type '$type'.");
    }
}

sub _build_query {
    my ($self, $query) = @_;

    is_hash_ref($query) or croak $self->_error("The QUERY argument must be a hash-ref.");

    return '?'. join('&', map {$_ . '=' . uri_escape($query->{$_})} keys %$query);
}

sub GET {
    my ($self, $path, $query) = @_;

    $path .= $self->_build_query($query) if $query;

    $self->{rest}->GET($path);

    return $self->_content();
}

sub DELETE {
    my ($self, $path, $query) = @_;

    $path .= $self->_build_query($query) if $query;

    $self->{rest}->DELETE($path);

    return $self->_content();
}

sub PUT {
    my ($self, $path, $query, $value, $headers) = @_;

    defined $value
        or croak $self->_error("PUT method's 'value' argument is undefined.");

    $path .= $self->_build_query($query) if $query;

    $headers                   //= {};
    $headers->{'Content-Type'} //= 'application/json;charset=UTF-8';

    $self->{rest}->PUT($path, $self->{json}->encode($value), $headers);

    return $self->_content();
}

sub POST {
    my ($self, $path, $query, $value, $headers) = @_;

    defined $value
        or croak $self->_error("POST method's 'value' argument is undefined.");

    $path .= $self->_build_query($query) if $query;

    $headers                   //= {};
    $headers->{'Content-Type'} //= 'application/json;charset=UTF-8';

    $self->{rest}->POST($path, $self->{json}->encode($value), $headers);

    return $self->_content();
}

sub set_search_iterator {
    my ($self, $params) = @_;

    my %params = ( %$params );  # rebuild the hash to own it

    $params{startAt} = 0;

    $self->{iter} = {
        params  => \%params,    # params hash to be used in the next call
        offset  => 0,           # offset of the next issue to be fetched
        results => {            # results of the last call (this one is fake)
            startAt => 0,
            total   => -1,
            issues  => [],
        },
    };

    return;
}

sub next_issue {
    my ($self) = @_;

    my $iter = $self->{iter}
        or croak $self->_error("You must call set_search_iterator before calling next_issue");

    if ($iter->{offset} == $iter->{results}{total}) {
        # This is the end of the search results
        $self->{iter} = undef;
        return;
    } elsif ($iter->{offset} == $iter->{results}{startAt} + @{$iter->{results}{issues}}) {
        # Time to get the next bunch of issues
        $iter->{params}{startAt} = $iter->{offset};
        $iter->{results}         = $self->POST('/search', undef, $iter->{params});
    }

    return $iter->{results}{issues}[$iter->{offset}++ - $iter->{results}{startAt}];
}

1;


__END__

=head1 SYNOPSIS

    use JIRA::REST;

    my $jira = JIRA::REST->new('https://jira.example.net', 'myuser', 'mypass');

    # File a bug
    my $issue = $jira->POST('/issue', undef, {
        fields => {
            project   => { key => 'PRJ' },
            issuetype => { name => 'Bug' },
            summary   => 'Cannot login',
            description => 'Bla bla bla',
        },
    });

    # Get issue
    $issue = $jira->GET("/issue/TST-101");

    # Iterate on issues
    my $search = $jira->POST('/search', undef, {
        jql        => 'project = "TST" and status = "open"',
        startAt    => 0,
        maxResults => 16,
        fields     => [ qw/summary status assignee/ ],
    });

    foreach my $issue (@{$search->{issues}}) {
        print "Found issue $issue->{key}\n";
    }

    # Iterate using utility methods
    $jira->set_search_iterator({
        jql        => 'project = "TST" and status = "open"',
        maxResults => 16,
        fields     => [ qw/summary status assignee/ ],
    });

    while (my $issue = $jira->next_issue) {
        print "Found issue $issue->{key}\n";
    }

=head1 DESCRIPTION

L<JIRA|http://www.atlassian.com/software/jira/> is a proprietary bug
tracking system from Atlassian.

This module implements a very thin wrapper around L<JIRA's REST
API|https://docs.atlassian.com/jira/REST/latest/> which is superseding
it's old L<SOAP
API|http://docs.atlassian.com/software/jira/docs/api/rpc-jira-plugin/latest/com/atlassian/jira/rpc/soap/JiraSoapService.html>
for which there is another Perl module called
L<JIRA::Client|http://search.cpan.org/dist/JIRA-Client/>.

=head1 CONSTRUCTOR

=head2 new URL, USERNAME, PASSWORD [, REST_CLIENT_CONFIG]

The constructor needs up to four arguments:

=over

=item * URL

A string or a URI object denoting the base URL of the JIRA
server. This is a required argument.

You may choose a specific API version by appending the
C</rest/api/VERSION> string to the URL's path. It's more common to
left it unspecified, in which case the C</rest/api/latest> string is
appended automatically to the URL.

=item * USERNAME

The username of a JIRA user.

It can be undefined if PASSWORD is also undefined. In such a case the
user credentials are looked up in the C<.netrc> file.

=item * PASSWORD

The HTTP password of the user. (This is the password the user uses to
log in to JIRA's web interface.)

It can be undefined, in which case the user credentials are looked up
in the C<.netrc> file.

=item * REST_CLIENT_CONFIG

A JIRA::REST object uses a REST::Client object to make the REST
invocations. This optional argument must be a hash-ref that can be fed
to the REST::Client constructor. Note that the C<URL> argument
overwrites any value associated with the C<host> key in this hash.

=back

=head1 REST METHODS

JIRA's REST API documentation lists dozens of "resources" which can be
operated via the standard HTTP requests: GET, DELETE, PUT, and
POST. JIRA::REST objects implement four methods called GET, DELETE,
PUT, and POST to make it easier to invoke and get results from JIRA's
REST endpoints.

All four methods need two arguments:

=over

=item * RESOURCE

This is the resource's 'path', minus the API version prefix. For
example, in order to GET the list of all fields, you must pass simply
C</field>, not C</rest/api/latest/field>, and in order to get a list
of all the components of a project, you must pass simply
C</project/$key/components>, not
C</rest/api/latest/project/$key/components>.

This argument is required.

=item * QUERY

Some resource methods require or admit parameters which are passed as
a C<query-string> appended to the resource's path. You may construct
the query string and append it to the RESOURCE argument yourself, but
it's easier and safer to pass the arguments in a hash. This way the
query string is constructed for you and its values are properly
L<percent-encoded|http://en.wikipedia.org/wiki/Percent-encoding> to
avoid errors.

This argument is optional for GET and DELETE. For PUT and POST it must
be passed explicitly as C<undef> if not needed.

=back

The PUT and POST methods accept two more arguments:

=over

=item * VALUE

This is the "entity" being PUT or POSTed. It can be any value, but
usually is a hash-ref. The value is encoded as a
L<JSON|http://www.json.org/> string using the C<JSON::encode> method
and sent with a Content-Type of C<application/json>.

It's usually easy to infer from the JIRA REST API documentation which
kind of value you should pass to each resource.

This argument is required.

=item * HEADERS

This optional argument allows you to specify extra HTTP headers that
should be sent with the request. Each header is specified as a
key/value pair in a hash.

=back

All four methods return the value returned by the associated
resource's method, as specified in the documentation, decoded
according to its content type as follows:

=over

=item * application/json

The majority of the API's resources return JSON values. Those are
decoded using the C<decode> method of a C<JSON> object. Most of the
endpoints return hashes, which are returned as a Perl hash-ref.

=item * text/plain

Those values are returned as simple strings.

=back

Some endpoints don't return anything. In those cases, the methods
return C<undef>. The methods croak if they get any other type of
values in return.

In case of errors (i.e., if the underlying HTTP method return an error
code different from 2xx) the methods croak with a multi-line string
like this:

    ERROR: <CODE> - <MESSAGE>
    <CONTENT-TYPE>
    <CONTENT>

So, in order to treat errors you must invoke the methods in an eval
block or use any of the exception handling Perl modules, such as
C<Try::Tiny> and C<Try::Catch>.

=head2 GET RESOURCE [, QUERY]

Returns the RESOURCE as a Perl data structure.

=head2 DELETE RESOURCE [, QUERY]

Deletes the RESOURCE.

=head2 PUT RESOURCE, QUERY, VALUE [, HEADERS]

Creates RESOURCE based on VALUE.

=head2 POST RESOURCE, QUERY, VALUE [, HEADERS]

Updates RESOURCE based on VALUE.

=head1 UTILITY METHODS

This module provides a few utility methods.

=head2 B<set_search_iterator> PARAMS

Sets up an iterator for the search specified by the hash-ref PARAMS. It must
be called before calls to B<next_issue>.

PARAMS must conform with the query parameters allowed for the
C</rest/api/2/search> JIRA REST endpoint.

=head2 B<next_issue>

This must be called after a call to B<set_search_iterator>. Each call
returns a reference to the next issue from the filter. When there are no
more issues it returns undef.

Using the set_search_iterator/next_issue utility methods you can iterate
through large sets of issues without worrying about the startAt/total/offset
attributes in the response from the /search REST endpoint. These methods
implement the "paging" algorithm needed to work with those attributes.

=head1 SEE ALSO

=over

=item * C<REST::Client>

JIRA::REST uses a REST::Client object to perform the low-level interactions.

=item * C<JIRA::Client>

JIRA::Client is another Perl module implementing the other JIRA
API based on SOAP.

=item * C<JIRA::Client::REST>

This is another module implementing JIRA's REST API using
L<SPORE|https://github.com/SPORE/specifications/blob/master/spore_description.pod>.
I got a message from the author saying that he doesn't intend to keep
it going.

=back

=head1 REPOSITORY

L<https://github.com/gnustavo/JIRA-REST>
