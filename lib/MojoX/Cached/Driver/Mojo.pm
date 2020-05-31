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
    my $cb;
    $cb = pop if ref $_[-1] eq 'CODE';

    my ( $self, $key, $opts ) = @_;

    my $data = $self->_instance->get($key)
        or return $cb ? $cb->($self) : ();

    $opts //= {};
    my $t = $opts->{t} // time;

    # If expired
    if ( $data->{expire_at} && $data->{expire_at} < $t ) {
        if ($cb) {
            return $self->expire( $key, sub { $cb->($self) } );
        }
        else {
            $self->expire($key);
            return;
        }
    }

    return $cb ? $cb->( $self, $data ) : $data;
}

sub set {
    my $cb;
    $cb = pop if ref $_[-1] eq 'CODE';
    my ( $self, $key, $value, $opts ) = @_;

    $opts //= {};
    my $expire_in = $opts->{expire_in} // $self->expire_in;
    my $t         = $opts->{t}         // time;

    my $data = {
        value     => $value,
        expire_at => $expire_in ? ( $t + $expire_in ) : (undef),
    };

    $self->_instance->set( $key, $data );

    return $cb ? $cb->( $self, $data ) : $data;
}

sub expire {
    my ( $self, $key, $cb ) = @_;

    for my $idx ( 0 .. $#{ $self->_instance->{queue} } ) {
        if ( $self->_instance->{queue}[$idx] eq $key ) {
            splice @{ $self->_instance->{queue} }, $idx, 1;
            delete $self->_instance->{cache}{$key};

            return $cb ? $cb->( $self, 1 ) : 1;
        }
    }

    return $cb ? $cb->( $self, !!0 ) : !!0;
}

sub flush {
    my ( $self, $cb ) = @_;

    $self->_instance->{queue} = [];
    $self->_instance->{cache} = {};

    return $cb ? $cb->($self) : ();
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
