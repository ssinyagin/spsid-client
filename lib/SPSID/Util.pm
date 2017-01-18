# Utilities for client applications

package SPSID::Util;

use Moose;

has 'client' =>
    (
     is  => 'ro',
     isa => 'Object',
     required => 1,
    );

has 'schema' =>
    (
     is  => 'rw',
     isa => 'HashRef',
    );


sub sync_contained_objects
{
    my $self = shift;
    my $container = shift;
    my $objclass = shift;
    my $sync_objects = shift;
    my $key_attrs = shift;
    
    my $schema = $self->schema;
    if( not defined($schema) )
    {
        $schema = $self->client->get_schema();
        $self->schema($schema);
    }
    
    if( not defined($schema->{$objclass}) ) {
        die('The schema does not contain class ' . $objclass);
    }
    
    if( not defined($schema->{$objclass}{'attr'}) ) {
        die('The schema for ' . $objclass . ' does not have "attr" map');
    }
    
    my $attr_schema = $schema->{$objclass}{'attr'};
    
    if( not defined($key_attrs) )
    {
        my @unique_mandatory_attr;
    
        foreach my $attr_name (sort keys %{$attr_schema}) {
            if( $attr_schema->{$attr_name}{'mandatory'}
                and
                (
                 $attr_schema->{$attr_name}{'unique'}
                 or
                 $attr_schema->{$attr_name}{'unique_child'}
                )
                and
                not $attr_schema->{$attr_name}{'default_autogen'} )
            {
                push(@unique_mandatory_attr, $attr_name);
            }
        }
        
        if( scalar(@unique_mandatory_attr) == 0 ) {
            die('The schema for ' . $objclass .
                ' does not have any unique+mandatory attributes');
        }

        $key_attrs = [ $unique_mandatory_attr[0] ];
    }        

    my $db_objects = $self->client->search_objects($container, $objclass);

    # index objects by key attributes
    
    my %db_uniqref;
    foreach my $obj (@{$db_objects}) {
        my $key = '';
        foreach my $key_attr (@{$key_attrs}) {
            $key .= lc($obj->{$key_attr}) . '%%%%%';
        }
        $db_uniqref{$key} = $obj;
    }

    # replace all undefs with empty strings
    foreach my $obj (@{$sync_objects}) {
        foreach my $key (keys %{$obj}) {
            if( not defined($obj->{$key}) ) {
                $obj->{$key} = '';
            }
        }
    }                
    
    my %sync_uniqref;
    foreach my $obj (@{$sync_objects}) {
        my $key;
        foreach my $key_attr (@{$key_attrs}) {
            if( not defined($obj->{$key_attr}) ) {
                if( defined($attr_schema->{$key_attr}{'default'}) )
                {
                    $obj->{$key_attr} =
                        $attr_schema->{$key_attr}{'default'};
                }
                else
                {
                    die('Key attribute ' . $key_attr . ' is missing in ' .
                        'a sync object and there is no default value');
                }
            }

            $key .= lc($obj->{$key_attr}) . '%%%%%';
        }
        
        if( defined($sync_uniqref{$key}) ) {
            die('Key attributes [' . join(',', @{$key_attrs}) .
                '] have a duplicate value ' . $key . ' in sync objects');
        }
        $sync_uniqref{$key} = $obj;
    }

    my @add_objects;
    my %modify_objects;
    my @delete_objects;

    my %ignore_attr =
        ('spsid.object.id' => 1,
         'spsid.object.class' => 1,
         'spsid.object.container' => 1);

    my %def_auto_attr;

    foreach my $attr_name (keys %{$attr_schema}) {
        if( $attr_schema->{$attr_name}{'calculated'} or
            $attr_schema->{$attr_name}{'sync_ignore'} )
        {
            $ignore_attr{$attr_name} = 1;
        }

        if( $attr_schema->{$attr_name}{'default_autogen'} )
        {
            $def_auto_attr{$attr_name} = 1;
        }
    }
    
    # Find objects for adding or modifying

    while( my ($key, $sync_obj) = each %sync_uniqref )
    {
        my $db_obj = $db_uniqref{$key};
        if( defined($db_obj) )
        {
            # check if the database object is to be modified or deleted
            # default_autogen attributes cannot be deleted, but
            # can be overwritten
            
            my $mod_obj = {};
            foreach my $attr_name (keys %{$db_obj}) {
                if( not $ignore_attr{$attr_name} )
                {
                    if( not defined($sync_obj->{$attr_name}) )
                    {
                        if( not $def_auto_attr{$attr_name} ) {
                            # deleted attribute
                            $mod_obj->{$attr_name} = undef;
                        }
                    }
                    elsif( $sync_obj->{$attr_name} ne $db_obj->{$attr_name} ) {
                        # modified attribute
                        $mod_obj->{$attr_name} = $sync_obj->{$attr_name};
                    }
                }
            }

            # check if attributes need to be added
            
            foreach my $attr_name (keys %{$sync_obj}) {
                if( not $ignore_attr{$attr_name} ) {
                    if( not defined($db_obj->{$attr_name}) ) {
                        # added attribute
                        $mod_obj->{$attr_name} = $sync_obj->{$attr_name};
                    }
                }
            }

            if( scalar(keys(%{$mod_obj})) > 0 ) {
                $modify_objects{$db_obj->{'spsid.object.id'}} = $mod_obj;
            }
        }
        else {
            # add object
            my $new_obj = {};
            
            foreach my $attr_name (keys %{$sync_obj}) {
                if( not $ignore_attr{$attr_name} )
                {
                    $new_obj->{$attr_name} = $sync_obj->{$attr_name};
                }
            }

            if( scalar(keys %def_auto_attr) > 0 )
            {
                $new_obj =
                    $self->client->new_object_default_attrs
                        ($container, $objclass, $new_obj);
            }

            $new_obj->{'spsid.object.container'} = $container;

            push(@add_objects, $new_obj);
        }
    }
    
    # find objects for deletion

    while( my ($key, $db_obj) = each %db_uniqref )
    {
        if( not defined($sync_uniqref{$key}) ) {
            push(@delete_objects, $db_obj);
        }
    }

    foreach my $obj ( @add_objects ) {
        $self->client->create_object($objclass, $obj);
    }

    foreach my $id ( keys %modify_objects ) {
        $self->client->modify_object($id, $modify_objects{$id});
    }

    foreach my $obj ( @delete_objects ) {
        $self->client->delete_object($obj->{'spsid.object.id'});
    }
    
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
