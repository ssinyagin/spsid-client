package SIAM::Driver::SPSID;

use warnings;
use strict;

use SPSID::Client;
use SPSID::Util;
use CHI;
use JSON;

=head1 NAME


SIAM::Driver::SPSID - SIAM Driver that works with SPSID server


=cut


=head1 SYNOPSIS

This driver connects to an SPSID database server and presents its
content to the SIAM API.

=head1 MANDATORY METHODS

The following methods are required by C<SIAM::Documentation::DriverSpec>.


=head2 new

Instantiates a new driver object. The method expects a hashref
containing the attributes, as follows:

=over 4

=item * Logger

The logger object is supplied by SIAM.

=item * SPSID_URL

SPSID server URL

=item * SPSID_REALM

Authentication realm

=item * SPSID_USER

Authentication user name

=item * SPSID_PW

Password

=back

=cut

sub new
{
    my $class = shift;
    my $drvopts = shift;

    my $self = {};
    bless $self, $class;

    $self->{'logger'} = $drvopts->{'Logger'};
    die('Logger is not supplied to the driver')
        unless defined($self->{'logger'});
    
    foreach my $param ('SPSID_URL', 'SPSID_REALM', 'SPSID_USER', 'SPSID_PW')
    {
        if( not defined($drvopts->{$param}) )
        {
            $self->error('Missing mandatory parameter ' . $param .
                         ' in SIAM::Driver::SPSID->new()');
            return undef;
        }
    }

    $self->{'client'} = 
        SPSID::Client->new_from_urlparams
              ({'url'      => $drvopts->{'SPSID_URL'},
                'realm'    => $drvopts->{'SPSID_REALM'},
                'username' => $drvopts->{'SPSID_USER'}, 
                'password' => $drvopts->{'SPSID_PW'}});
    
    $self->{'url'} = $drvopts->{'SPSID_URL'};

    $self->{'cache'} = 
        CHI->new( driver => 'RawMemory',
                  expires_in => 10,
                  datastore => {} );
    
    return $self;    
}


sub client {return shift->{'client'}};

# get the SPSID object attributes by Id
sub _spsid_obj
{
    my $self = shift;
    my $id = shift;
    
    my $spsid_obj = $self->{'cache'}->get($id);
    if( not defined($spsid_obj) )
    {
        $spsid_obj = $self->client->get_object($id);
        $self->{'cache'}->set($id, $spsid_obj);
    }

    return $spsid_obj;
}


sub _spsid_objlist_to_idlist
{
    my $self = shift;
    my $objects = shift;
    
    my $ret = [];
    foreach my $spsid_obj (@{$objects})
    {
        my $id = $spsid_obj->{'spsid.object.id'};
        $self->{'cache'}->set($id, $spsid_obj);
        push(@{$ret}, $id);
    }
    return $ret;
}



=head2 connect

Tries to reach the SPSID server and checks the connection.

=cut

sub connect
{
    my $self = shift;

    $self->debug('Checking SPSID connection at ' . $self->{'url'});
    
    eval { $self->client->ping() };
    if( $@ )
    {
        $self->error('Cannot connect to SPSID server at ' .
                     $self->{'url'} . ': ' . $@);
        return undef;
    }

    $self->{'root'} = $self->client->get_siam_root();
    if( not defined($self->{'root'}) )
    {
        $self->error('Cannot find SIAM root in SPSID at ' . $self->{'url'});
        return undef;
    }
    
    return 1;
}



=head2 disconnect

Does nothing.

=cut

sub disconnect
{
    my $self = shift;
    $self->{'cache'}->clear();
    return;
}


=head2 fetch_attributes

 $status = $driver->fetch_attributes($attrs);

Retrieve the object by ID and populate the hash with object attributes.

=cut

my %spsid_attr_translation =
    (
     'spsid.object.container' => 'siam.object.container',
    );

sub fetch_attributes
{
    my $self = shift;
    my $obj = shift;

    my $id = $obj->{'siam.object.id'};
    if( not defined($id) )
    {
        $self->error('siam.object.id is not specified in fetch_attributes' );
        return undef;
    }

    if( $id eq 'SIAM.ROOT' )
    {
        return 1;
    }
    
    my $spsid_obj = $self->_spsid_obj($id);
    
    while(my($key,$val) = each %{$spsid_obj})
    {
        if($key =~ /^spsid\./o)
        {
            if( defined($spsid_attr_translation{$key}) )
            {
                $obj->{$spsid_attr_translation{$key}} = $val;
            }
        }
        else
        {
            $obj->{$key} = $val;
        }
    }
            
    return 1;
}
    

=head2 fetch_computable

  $value = $driver->fetch_computable($id, $key);

Retrieve a computable. Return empty string if unsupported.

=cut

sub fetch_computable
{
    my $self = shift;
    my $id = shift;
    my $key = shift;

    if( $key eq 'siam.contract.content_md5hash' )
    {
        return $self->client->recursive_md5($id);
    }
    
    return '';
}
            


=head2 fetch_contained_object_ids

   $ids = $driver->fetch_contained_object_ids($id, 'SIAM::Contract', {
       'match_attribute' => [ 'siam.object.access_scope_id',
                              ['SCOPEID01', 'SCOPEID02'] ]
      }
     );

Retrieve the contained object IDs.

=cut

sub fetch_contained_object_ids
{
    my $self = shift;
    my $container_id = shift;
    my $class = shift;
    my $options = shift;

    if( $container_id eq 'SIAM.ROOT' )
    {
        $container_id = $self->{'root'};
    }
    
    my $objects;

    if( not defined($options) )
    {
        $objects = $self->client->search_objects($container_id, $class);
    }
    else
    {
        if( defined($options->{'match_attribute'}) )
        {
            my ($filter_attr, $filter_val) = @{$options->{'match_attribute'}};

            my $objhash = {};
            
            foreach my $val (@{$filter_val})                
            {
                my $r =
                    $self->client->search_objects($container_id, $class,
                                                  $filter_attr, $val);
                foreach my $spsid_obj (@{$r})
                {
                    $objhash->{$spsid_obj->{'spsid.object.id'}} = $spsid_obj;
                }
            }

            $objects = [values %{$objhash}];
        }
    }

    return $self->_spsid_objlist_to_idlist($objects);
}



=head2 fetch_contained_classes

  $classes = $driver->fetch_contained_classes($id);

Returns arrayref with class names.

=cut

sub fetch_contained_classes
{
    my $self = shift;
    my $id = shift;

    if( $id eq 'SIAM.ROOT' )
    {
        $id = $self->{'root'};
    }
    
    return $self->client->contained_classes($id);
}


=head2 fetch_container

  $attr = $driver->fetch_container($id);

Retrieve the container ID and class.

=cut

sub fetch_container
{
    my $self = shift;
    my $id = shift;

    my $this_spsid_obj = $self->_spsid_obj($id);
    
    my $container_id = $this_spsid_obj->{'spsid.object.container'};
    if( not defined($container_id) )
    {
        return undef;
    }

    if( $container_id eq $self->{'root'} )
    {
        return {'siam.object.id' => 'SIAM.ROOT'};
    }

    my $spsid_container_obj = $self->_spsid_obj($container_id);
    
    my $ret =
    {
     'siam.object.id' => $container_id,
     'siam.object.class' => $spsid_container_obj->{'spsid.object.class'},
    };
    
    return $ret;
}


=head2 fetch_object_ids_by_attribute

  $list = $driver->fetch_object_ids_by_attribute($classname, $attr, $value);

Returns a list of object IDs which match the attribute value.

=cut

sub fetch_object_ids_by_attribute
{
    my $self = shift;
    my $class = shift;
    my $attr = shift;
    my $value = shift;
    
    my $objects = $self->client->search_objects(undef, $class, $attr, $value);
    return $self->_spsid_objlist_to_idlist($objects);    
}
        


=head2 set_condition

Implements conditgions for certain object classes. For others, simply
sets an attribute in SPSID.

=cut

sub set_condition
{
    my $self = shift;
    my $id = shift;    
    my $key = shift;
    my $value = shift;

    $self->debug('set_condition is called for ' . $id . ': (' .
                 $key . ', ' . $value . ')');

    my $spsid_obj = $self->_spsid_obj($id);
    my $class = $spsid_obj->{'spsid.object.class'};

    my $handled = 0;
    
    if( $class eq 'SIAM::Device' )
    {
        if( $key eq 'siam.device.set_components' )
        {
            my $objects = eval { decode_json($value) };
            if( $@ )
            {
                $self->error('Cannot decode JSON value in ' . $key .
                             ' condition :' . $@);
                return;
            }

            if( ref($objects) ne 'ARRAY' )
            {
                $self->error('The condition value is not a JSON array in ' .
                             $key . ': ' . $value);
                return;
            }
            
            my $util = SPSID::Util->new(client => $self->client);            
            eval { $util->sync_contained_objects
                       ($id, 'SIAM::DeviceComponent', $objects) };
            if( $@ )
            {
                $self->error('Condition ' . $key .
                             ' failed to apply :' . $@);
                return;
            }

            $handled = 1;
        }
    }

    if( not $handled )
    {
        eval { $self->client->modify_object($id, {$key => $value}) };
        if( $@ )
        {
            $self->error('Condition ' . $key .
                         ' failed to apply :' . $@);
            return;
        }
    }

    $self->{'cache'}->clear();
    return;
}


=head2 manifest_attributes

The method returns an arrayref with all known attribute names.

=cut

sub manifest_attributes
{
    my $self = shift;
    return [];
}




=head1 ADDITIONAL METHODS

The following methods are not in the Specification.


=head2 debug

Prints a debug message to the logger.

=cut

sub debug
{
    my $self = shift;
    my $msg = shift;    
    $self->{'logger'}->debug($msg);
}


=head2 error

Prints an error message to the logger.

=cut

sub error
{
    my $self = shift;
    my $msg = shift;    
    $self->{'logger'}->error($msg);
}





=head1 SEE ALSO

L<SIAM::Documentation::DriverSpec>, L<YAML>, L<Log::Handler>

=cut

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
