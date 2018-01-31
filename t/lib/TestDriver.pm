package TestDriver;

use Mojo::Base 'MojoX::Cached::Driver';

has cache => sub { return {} };
has status => sub { [] };

sub clear_status { shift->{status} = [] }

sub get {
    my ( $self, $key, $cb ) = @_;

    push( @{ $self->status }, 'get' );
    my $data = $self->cache->{$key}
        or return $cb ? $cb->($self) : ();

    if ( $data->{expire_at} && $data->{expire_at} < time ) {
        $self->expire( $key, ( $cb ? sub { $cb->($self) } : () ) );
        return;
    }

    return $cb ? $cb->( $self, $data ) : $data;
}

sub set {
    my $cb = pop if ref $_[-1] eq 'CODE';
    my ( $self, $key, $value, $expire_in ) = @_;

    push( @{ $self->status }, 'set' );
    my $data = {
        value     => $value,
        expire_at => $expire_in ? ( time + $expire_in ) : (undef),
    };

    $self->cache->{$key} = $data;

    return $cb ? $cb->( $self, $data ) : $data;
}

sub expire {
    my ( $self, $key, $cb ) = @_;

    push( @{ $self->status }, 'expire' );
    my $status = exists $self->cache->{$key};
    delete $self->cache->{$key};

    return $cb ? $cb->( $self, $status ) : $status;
}

sub flush {
    my ( $self, $cb ) = @_;

    push( @{ $self->status }, 'flush' );
    $self->cache( {} );

    return $cb ? $cb->($self) : ();
}


1;
