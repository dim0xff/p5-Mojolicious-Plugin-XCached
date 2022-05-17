package TestDriver;

use Mojo::Base 'MojoX::Cached::Driver';

has cache => sub { return {} };
has status => sub { [] };

sub clear_status { shift->{status} = [] }

sub get {
    my $cb;
    $cb = pop if ref $_[-1] eq 'CODE';

    my ( $self, $key, $opts ) = @_;

    push( @{ $self->status }, 'get' );
    my $data = $self->cache->{$key}
        or return $cb ? $cb->($self) : ();

    $opts //= {};
    my $t = $opts->{t} // time;

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

    push( @{ $self->status }, 'set' );
    my $data = {
        value     => $value,
        expire_at => $expire_in ? ( $t + $expire_in ) : (undef),
    };

    $self->cache->{$key} = $data;

    return $cb ? $cb->( $self, $data ) : $data;
}

sub expire {
    my $cb;
    $cb = pop if ref $_[-1] eq 'CODE';
    my ( $self, $key, $opts ) = @_;

    push( @{ $self->status }, 'expire' );
    my $status = exists $self->cache->{$key};
    delete $self->cache->{$key};

    return $cb ? $cb->( $self, !!$status ) : !!$status;
}

sub flush {
    my $cb;
    $cb = pop if ref $_[-1] eq 'CODE';
    my ( $self, $opts ) = @_;

    push( @{ $self->status }, 'flush' );
    $self->cache( {} );

    return $cb ? $cb->($self) : ();
}


1;
