package TestDriverDeffer;

use Mojo::Base 'MojoX::Cached::Driver';

use Mojo::IOLoop;
use Mojo::Promise;

has speed => 0;
has cache => sub { return {} };
has status => sub { [] };

sub clear_status { shift->{status} = [] }

sub get {
    my $cb;
    $cb = pop if ref $_[-1] eq 'CODE';

    my ( $self, $key, $opts ) = @_;

    $opts //= {};
    my $t = $opts->{t} // time;

    my $p = Mojo::Promise->new;

    my $data;
    Mojo::IOLoop->timer(
        $self->speed => sub {
            push( @{ $self->status }, 'get' );

            $data = $self->cache->{$key};

            if ( !$data ) {
                $cb->($self) if $cb;
            }
            elsif ( $data->{expire_at} && $data->{expire_at} < $t ) {
                if ($cb) {
                    $self->expire( $key, sub { $cb->($self) } );
                }
                else {
                    $self->expire($key);
                }
            }
            else {
                $cb->( $self, $data );
            }

            $p->resolve;
        }
    );
    $p->wait;

    return $data ? $cb ? 1 : $data : ();
}

sub set {
    my $cb;
    $cb = pop if ref $_[-1] eq 'CODE';
    my ( $self, $key, $value, $opts ) = @_;

    $opts //= {};
    my $expire_in = $opts->{expire_in} // $self->expire_in;
    my $t         = $opts->{t}         // time;

    my $p = Mojo::Promise->new;

    my $data;
    Mojo::IOLoop->timer(
        $self->speed => sub {
            push( @{ $self->status }, 'set' );

            $data = {
                value     => $value,
                expire_at => $expire_in ? ( $t + $expire_in ) : (undef),
            };

            $self->cache->{$key} = $data;
            $cb->( $self, $data ) if $cb;

            $p->resolve;
        }
    );
    $p->wait;


    return $cb ? 1 : $data;
}

sub expire {
    my ( $self, $key, $cb ) = @_;

    my $p = Mojo::Promise->new;

    my $status;
    Mojo::IOLoop->timer(
        $self->speed => sub {
            push( @{ $self->status }, 'expire' );

            $status = exists $self->cache->{$key};
            delete $self->cache->{$key};

            $cb->( $self, !!$status ) if $cb;

            $p->resolve;
        }
    );
    $p->wait;

    return $cb ? 1 : !!$status;
}

sub flush {
    my ( $self, $cb ) = @_;

    my $p = Mojo::Promise->new;

    my $status;
    Mojo::IOLoop->timer(
        $self->speed => sub {
            push( @{ $self->status }, 'flush' );
            $self->cache( {} );

            $cb->($self) if $cb;

            $p->resolve;
        }
    );
    $p->wait;

    return $cb ? 1 : ();
}


1;
