# Simple JSON-RPC 2.0 client for SPSID communicatoin.

package SPSID::Client;

use utf8;
use JSON;
use LWP::UserAgent;
use HTTP::Request;
use URI;
use Getopt::Long;

use Moose;


has 'url' =>
    (
     is  => 'rw',
     isa => 'Str',
     required => 1,
    );
    
has 'ua' =>
    (
     is  => 'rw',
     isa => 'Object',
    );

has _next_id => (
    is      => 'ro',
    isa     => 'CodeRef',
    lazy    => 1,
    default => sub {
        my $id = 0;
        sub { ++$id };
    },
);



sub BUILD
{
    my $self = shift;

    if( not defined($self->ua) ) {
        my $ua = LWP::UserAgent->new;
        $ua->timeout(10);
        $ua->env_proxy;
        $self->ua($ua);
    }
    
    return;
}


sub new_from_getopt
{
    my $url = $ENV{'SPSID_URL'};
    my $realm = $ENV{'SPSID_REALM'};
    my $username = $ENV{'SPSID_USER'};
    my $password = $ENV{'SPSID_PW'};

    my $p = new Getopt::Long::Parser;
    $p->configure('pass_through');
    if( not $p->getoptions('url=s'   => \$url,
                           'realm=s' => \$realm,
                           'user=s'  => \$username,
                           'pw=s'    => \$password) ) {
        die('Cannot parse command-line options');
    }

    die("--url option is required\n") unless defined($url);

    return SPSID::Client->new_from_urlparams
        ({'url' => $url,
          'realm' => $realm,
          'username' => $username,
          'password' => $password});
}


sub getopt_help_string
{
    return join("\n",
                "  --url=URL      SPSID RPC location",
                "  --realm=X      HTTP authentication realm",
                "  --user=X       HTTP authentication user",
                "  --pw=X         HTTP authentication password",
                "");
}

sub cli_env_vars
{
    return join("\n",
                "Environment variables:",
                "   SPSID_URL, SPSID_REALM, SPSID_USER, SPSID_PW",
                "", "");
}
    
    

sub new_from_urlparams
{
    my $class = shift;
    my $params = shift;

    my $url = $params->{'url'};
    my $realm = $params->{'realm'};
    my $username = $params->{'username'};
    my $password = $params->{'password'};

    my $uri = URI->new($url);
    die('Cannot parse URL: ' . $url) unless defined $uri;

    my $ua = LWP::UserAgent->new(keep_alive => 1);
    $ua->timeout(10);
    $ua->env_proxy;

    if( defined($realm) or defined($username) or defined($password) ) {
        if( defined($realm) and defined($username) and defined($password) ) {
            $ua->credentials($uri->host_port, $realm, $username, $password);
        }
        else {
            die('Realm, user, and password are required at the same time');
        }
    }

    return SPSID::Client->new('url' => $url, 'ua' => $ua);
}    


sub _call
{
    my $self = shift;
    my $method = shift;
    my $params = shift;

    my $req = HTTP::Request->new( 'POST', $self->url );    
    $req->header( 'Content-Type' => 'application/json' );

    my $json = JSON->new->utf8(1);
    $req->content
        ( $json->encode
          ({'jsonrpc' => '2.0',
            'id'      => $self->_next_id->(),
            'method'  => $method,
            'params'  => $params}));
    
    my $response = $self->ua->request($req);

    my $rpc_error_msg = sub {
        my $r = shift;
        my $ret = 'JSON-RPC error ' . $r->{'error'}{'code'} . ': ' .
            $r->{'error'}{'message'};
        if( defined($r->{'error'}{'data'}) ) {
            $ret .= ' ' . $r->{'error'}{'data'};
        }
        return $ret;
    };
        
    if( $response->is_success ) {
        my $content = $response->decoded_content;
        my $result = decode_json($content);
        die('Cannot parse responce') unless defined($result);
        
        die('Missing version 2.0 in RPC response') unless
            (defined($result->{'jsonrpc'}) and $result->{'jsonrpc'} eq '2.0');
        
        if( defined($result->{'error'}) ) {            
            die(&{$rpc_error_msg}($result));
        }

        return $result->{'result'};
    }

    my $err_result;
    eval {$err_result = decode_json($response->decoded_content) };
    if( defined($err_result) and defined($err_result->{'error'}) ){
        die(&{$rpc_error_msg}($err_result));
    }
    else {
        die('HTTP error:' . $response->status_line);
    }
}





sub create_object
{
    my $self = shift;
    my $objclass = shift;
    my $attr = shift;

    return $self->_call('create_object', {'objclass' => $objclass,
                                          'attr' => $attr});
}



# modify or add or delete attributes of an object

sub modify_object
{
    my $self = shift;
    my $id = shift;
    my $mod_attr = shift;
    
    $self->_call('modify_object', {'id' => $id,
                                   'mod_attr' => $mod_attr});
    return;
}


sub validate_object
{
    my $self = shift;
    my $attr = shift;
    
    return $self->_call('validate_object', {'attr' => $attr});
}


sub delete_object
{
    my $self = shift;
    my $id = shift;

    $self->_call('delete_object', {'id' => $id});
    return;
}


sub get_object
{
    my $self = shift;
    my $id = shift;

    return $self->_call('get_object', {'id' => $id});
}

sub get_object_log
{
    my $self = shift;
    my $id = shift;

    return $self->_call('get_object_log', {'id' => $id});
}


# input: attribute names and values for AND condition
# output: arrayref of objects found

sub search_objects
{
    my $self = shift;
    my $container = shift;
    my $objclass = shift;

    my $arg = {'container' => $container,
               'objclass' => $objclass};
    if( scalar(@_) > 0 ) {
        $arg->{'search_attrs'} = [ @_ ];
    }
        
    return $self->_call('search_objects', $arg);
}


sub search_prefix
{
    my $self = shift;
    my $objclass = shift;
    my $attr_name = shift;
    my $attr_prefix = shift;

    return $self->_call('search_prefix', {'objclass' => $objclass,
                                          'attr_name' => $attr_name,
                                          'attr_prefix' => $attr_prefix});
}


sub contained_classes
{
    my $self = shift;
    my $container = shift;

    return $self->_call('contained_classes', {'container' => $container});
}


sub get_schema
{
    my $self = shift;
    return $self->_call('get_schema', {});
}
    

sub new_object_default_attrs
{
    my $self = shift;
    my $container = shift;
    my $objclass = shift;
    my $templatekeys = shift;
    
    return $self->_call('new_object_default_attrs',
                        {'container' => $container,
                         'objclass' => $objclass,
                         'templatekeys' => $templatekeys});
}


sub get_siam_root
{
    my $self = shift;
    my $r = $self->search_objects('NIL', 'SIAM');
    if( defined($r) and scalar(@{$r}) > 0 ) {
        return $r->[0]->{'spsid.object.id'};
    }
    else {
        return;
    }
}






sub ping
{
    my $self = shift;

    my $v = $self->_call('server_version');
    die('Server did not return its version')
        unless (defined($v) and $v > 0);

    if( $v < 1.0 ) {
        die('Server version is incompatible with the client');
    }
    
    my $r = $self->_call('ping', {'echo' => 'blahblah'});
    die('Ping RPC call returned wrong response')
        unless ($r->{'echo'} eq 'blahblah');
    return;
}


1;



# Local Variables:
# mode: cperl
# indent-tabs-mode: nil
# cperl-indent-level: 4
# cperl-continued-statement-offset: 4
# cperl-continued-brace-offset: -4
# cperl-brace-offset: 0
# cperl-label-offset: -2
# End:
