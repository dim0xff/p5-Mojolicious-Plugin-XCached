package TestDriver;

use Mojo::Base 'MojoX::Cached::Driver';

has cache => sub { return {} };
has status => sub { [] };

sub clear_status { shift->{status} = [] }

sub get {
    my ( $self, $key ) = @_;

    push( @{ $self->status }, 'get' );
    my $data = $self->cache->{$key} or return;

    if ( $data->{expire_at} && $data->{expire_at} < time ) {
        $self->expire($key);
        return;
    }

    return $data;
}

sub set {
    my ( $self, $key, $value, $expire_in ) = @_;

    push( @{ $self->status }, 'set' );
    my $data = {
        value     => $value,
        expire_at => $expire_in ? ( time + $expire_in ) : (undef),
    };

    $self->cache->{$key} = $data;

    return $data;
}

sub expire {
    my ( $self, $key ) = @_;

    push( @{ $self->status }, 'expire' );
    delete $self->cache->{$key};
}

sub flush {
    my $self = shift;

    push( @{ $self->status }, 'flush' );
    $self->cache( {} );
}


1;
