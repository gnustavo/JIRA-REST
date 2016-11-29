package JIRA::REST;
# ABSTRACT: Thin wrapper around JIRA's REST API

use 5.008_008;
use utf8;
use strict;
use warnings;

use Carp;
use URI;
use MIME::Base64;
use URI::Escape;
use JSON;
use REST::Client;

sub new {
    my ($class, $URL, $username, $password, $rest_client_config) = @_;

    # Make sure $URL isa URI
    if (! defined $URL) {
        croak __PACKAGE__ . "::new: URL argument must be defined.\n";
    } elsif (! ref $URL) {
        $URL = URI->new($URL);
    } elsif (! $URL->isa('URI')) {
        croak __PACKAGE__ . "::new: URL argument must be an URI object.\n";
    }

    # See if the user wants a specific JIRA Core REST API version:
    my $path = $URL->path('') || '/rest/api/latest';
    $path =~ m@^/rest/api/(?:latest|\d+)$@
        or croak __PACKAGE__ . "::new: invalid path in URL: '$path'\n";

    # If username and password are not set we try to lookup the credentials
    if (! defined $username || ! defined $password) {
        ($username, $password) = _search_for_credentials($URL, $username);
    }

    croak __PACKAGE__ . "::new: USERNAME argument must be a string.\n"
        unless defined $username && ! ref $username && length $username;

    croak __PACKAGE__ . "::new: PASSWORD argument must be a string.\n"
        unless defined $password && ! ref $password && length $password;

    $rest_client_config = {} unless defined $rest_client_config;
    croak __PACKAGE__ . "::new: REST_CLIENT_CONFIG argument must be a hash-ref.\n"
        unless
        defined $rest_client_config
        &&  ref $rest_client_config
        &&  ref $rest_client_config eq 'HASH';

    # remove the REST::Client faux config 'proxy' if set and use it later.
    my $proxy = delete $rest_client_config->{proxy};

    my $rest = REST::Client->new($rest_client_config);

    # Set proxy to be used
    $rest->getUseragent->proxy(['http','https'] => $proxy) if $proxy;

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
        path => $path,
    } => $class;
}

sub _search_for_credentials {
    my ($URL, $username) = @_;
    my (@errors, $password);

    # Try .netrc first
    ($username, $password) = eval { _user_pass_from_netrc($URL, $username) };
    push @errors, "Net::Netrc: $@" if $@;
    return ($username, $password) if defined $username && defined $password;

    # Fallback to Config::Identity
    my $stub = $ENV{JIRA_REST_IDENTITY} || "jira";
    ($username, $password) = eval { _user_pass_from_config_identity($stub) };
    push @errors, "Config::Identity: $@" if $@;
    return ($username, $password) if defined $username && defined $password;

    # Still not defined, so we report errors
    for (@errors) {
        chomp;
        s/\n//g;
        s/ at \S+ line \d+.*//;
    }
    croak __PACKAGE__ . "::new: Could not locate credentials. Tried these modules:\n"
        . join("", map { "* $_\n" } @errors)
        . "Please specify the USERNAME and PASSWORD as arguments to new";
}

sub _user_pass_from_config_identity {
    my ($stub) = @_;
    my ($username, $password);
    eval {require Config::Identity; Config::Identity->VERSION(0.0019) }
        or croak "Can't load Config::Identity 0.0019 or later.\n";
    my %id = Config::Identity->load_check( $stub, [qw/username password/] );
    return ($id{username}, $id{password});
}

sub _user_pass_from_netrc {
    my ($URL, $username) = @_;
    my $password;
    eval {require Net::Netrc; 1}
        or croak "Can't require Net::Netrc module.";
    if (my $machine = Net::Netrc->lookup($URL->host, $username)) { # $username may be undef
        $username = $machine->login;
        $password = $machine->password;
    } else {
        croak "No credentials found in the .netrc file.\n";
    }
    return ($username, $password);
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
    } elsif ($type =~ m:^(text/|application|xml):i) {
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

sub _build_path {
    my ($self, $path, $query) = @_;

    $path = $self->{path} . $path unless $path =~ m:/rest/:;

    if (defined $query) {
        croak $self->_error("The QUERY argument must be a hash-ref.")
            unless ref $query && ref $query eq 'HASH';
        return $path . '?'. join('&', map {$_ . '=' . uri_escape($query->{$_})} keys %$query);
    } else {
        return $path;
    }
}

sub GET {
    my ($self, $path, $query) = @_;

    $self->{rest}->GET($self->_build_path($path, $query));

    return $self->_content();
}

sub DELETE {
    my ($self, $path, $query) = @_;

    $self->{rest}->DELETE($self->_build_path($path, $query));

    return $self->_content();
}

sub PUT {
    my ($self, $path, $query, $value, $headers) = @_;

    defined $value
        or croak $self->_error("PUT method's 'value' argument is undefined.");

    $path = $self->_build_path($path, $query);

    $headers                   ||= {};
    $headers->{'Content-Type'}   = 'application/json;charset=UTF-8'
        unless defined $headers->{'Content-Type'};

    $self->{rest}->PUT($path, $self->{json}->encode($value), $headers);

    return $self->_content();
}

sub POST {
    my ($self, $path, $query, $value, $headers) = @_;

    defined $value
        or croak $self->_error("POST method's 'value' argument is undefined.");

    $path = $self->_build_path($path, $query);

    $headers                   ||= {};
    $headers->{'Content-Type'}   = 'application/json;charset=UTF-8'
        unless defined $headers->{'Content-Type'};

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

sub attach_files {
    my ($self, $issueIdOrKey, @files) = @_;

    # We need to violate the REST::Client class encapsulation to implement
    # the HTTP POST method necessary to invoke the /issue/key/attachments
    # REST endpoint because it has to use the form-data Content-Type.

    my $rest = $self->{rest};

    # FIXME: How to attach all files at once?
    foreach my $file (@files) {
        my $response = $rest->getUseragent()->post(
            $rest->getHost . "/issue/$issueIdOrKey/attachments",
            %{$rest->{_headers}},
            'X-Atlassian-Token' => 'nocheck',
            'Content-Type'      => 'form-data',
            'Content'           => [ file => [$file] ],
        );

        $response->is_success
            or croak $self->_error("attach_files($file): " . $response->status_line);
    }
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

    # Attach files using an utility method
    $jira->attach_files('TST-123', '/path/to/doc.txt', 'image.png');

=head1 DESCRIPTION

L<JIRA|http://www.atlassian.com/software/jira/> is a proprietary bug
tracking system from Atlassian.

This module implements a very thin wrapper around JIRA's REST APIs:

=over

=item * L<JIRA Core REST API|https://docs.atlassian.com/jira/REST/server/>

This rich API superseded the old L<JIRA SOAP
API|http://docs.atlassian.com/software/jira/docs/api/rpc-jira-plugin/latest/com/atlassian/jira/rpc/soap/JiraSoapService.html>
which isn't supported anymore as of JIRA version 7.

The endpoints of this API have a path prefix of C</rest/api/VERSION>.

=item * L<JIRA Service Desk REST API|https://docs.atlassian.com/jira-servicedesk/REST/server/>

This API deals with the objects of the JIRA Service Desk application. Its
endpoints have a path prefix of C</rest/servicedeskapi>.

=item * L<JIRA Software REST API|https://docs.atlassian.com/jira-software/REST/server/>

This API deals with the objects of the JIRA Software application. Its
endpoints have a path prefix of C</rest/agile/VERSION>.

=back

=head1 CONSTRUCTOR

=head2 new URL, USERNAME, PASSWORD [, REST_CLIENT_CONFIG]

The constructor needs up to four arguments:

=over

=item * URL

A string or a URI object denoting the base URL of the JIRA
server. This is a required argument.

The REST methods described below all accept as a first argument the
endpoint's path of the specific API method to call. In general you can pass
the complete path, beginning with the prefix denoting the particular API to
use (C</rest/api/VERSION>, C</rest/servicedeskapi>, or
C</rest/agile/VERSION>). However, to make it easier to invoke JIRA's Core
API if you pass a path not starting with C</rest/> it will be prefixed with
C</rest/api/latest> or with this URL's path if it has one. This way you can
choose a specific version of the JIRA Core API to use instead of the latest
one. For example:

    my $jira = JIRA::REST->new('https://jira.example.net/rest/api/1', 'myuser', 'mypass');

=item * USERNAME

The username of a JIRA user.

It can be undefined if PASSWORD is also undefined. In such a case the
user credentials are looked up in the C<.netrc> file or via
L<Config::Identity> (which allows C<gpg> encrypted credentials).

L<Config::Identity> will look for F<~/.jira-identity> or F<~/.jira>.
You can change the filename stub from C<jira> to a custom stub with the
C<JIRA_REST_IDENTITY> environment variable.

=item * PASSWORD

The HTTP password of the user. (This is the password the user uses to
log in to JIRA's web interface.)

It can be undefined, in which case the user credentials are looked up
in the C<.netrc> file or via L<Config::Identity>.

=item * REST_CLIENT_CONFIG

A JIRA::REST object uses a REST::Client object to make the REST
invocations. This optional argument must be a hash-ref that can be fed
to the REST::Client constructor. Note that the C<URL> argument
overwrites any value associated with the C<host> key in this hash.

To use a network proxy please set the 'proxy' argument to the string or URI
object describing the fully qualified (including port) URL to your network
proxy. This is an extension to the REST::Client configuration and will be
removed from the hash before passing it on to the REST::Client constructor.

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

This is the resource's 'path'. For example, in order to GET the list of all
fields, you pass C</rest/api/latest/field>, and in order to get SLA
information about an issue you pass
C</rest/servicedeskapi/request/$key/sla>.

If you're using a method form JIRA Core REST API you may ommit the prefix
C</rest/api/VERSION>. For example, to GET the list of all fields you may
pass just C</field>.

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

=head2 B<attach_files> ISSUE FILE...

The C</issue/KEY/attachments> REST endpoint, used to attach files to issues,
requires a specific content type encoding which is difficult to come up with
just the C<REST::Client> interface. This utility method offers an easier
interface to attach files to issues.

=head1 SEE ALSO

=over

=item * C<REST::Client>

JIRA::REST uses a REST::Client object to perform the low-level interactions.

=item * C<JIRA::Client::REST>

This is another module implementing JIRA's REST API using
L<SPORE|https://github.com/SPORE/specifications/blob/master/spore_description.pod>.
I got a message from the author saying that he doesn't intend to keep
it going.

=back

=head1 REPOSITORY

L<https://github.com/gnustavo/JIRA-REST>
