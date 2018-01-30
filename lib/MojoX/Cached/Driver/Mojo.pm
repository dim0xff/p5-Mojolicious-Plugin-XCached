package MojoX::Cached::Driver::Mojo;

# ABSTRACT: XCached driver built on top of L</Mojo::Cache>

use Mojo::Base 'MojoX::Cached::Driver';

use Mojo::Cache;

has '_instance';

sub new {
    my $class = shift;

    my %args = @_ ? @_ > 1 ? @_ : %{ $_[0] } : ();

    my $instance = Mojo::Cache->new( delete $args{driver} // {} );

    return $class->SUPER::new( %args, _instance => $instance );
}

sub get {
    my ( $self, $key ) = @_;

    my $data = $self->_instance->get($key) or return;

    # Expired
    if ( $data->{expire_at} && $data->{expire_at} < time ) {
        $self->expire($key);
        return;
    }

    return $data;
}

sub set {
    my ( $self, $key, $value, $expire_in ) = @_;

    my $data = {
        value     => $value,
        expire_at => $expire_in ? ( time + $expire_in ) : (undef),
    };

    $self->_instance->set( $key, $data );

    return $data;
}

sub expire {
    my ( $self, $key ) = @_;

    for my $idx ( 0 .. $#{ $self->_instance->{queue} } ) {
        if ( $self->_instance->{queue}[$idx] eq $key ) {
            splice @{ $self->_instance->{queue} }, $idx, 1;
            delete $self->_instance->{cache}{$key};
            return 1;
        }
    }

    return 0;
}

sub flush {
    my $self = shift;

    $self->_instance->{queue} = [];
    $self->_instance->{cache} = {};
}

1;

__END__

=head1 DESCRIPTION

Simple cache driver built on top of L<Mojo::Cache>.

L<Mojo::Cache> parameters could set via C<driver> option.

    use MojoX::Cached;
    use MojoX::Cached::Driver::Mojo;

    my $driver  = MojoX::Cached::Driver::Mojo->new( driver => { max_keys => 50 } );
    my $xcached = MojoX::Cached->new( driver => $driver, ... );
