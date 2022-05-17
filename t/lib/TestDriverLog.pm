package TestDriverLog;

use mro 'c3';

use Mojo::Base 'MojoX::Cached::Driver::Mojo';

has status => sub { [] };

sub clear_status { shift->{status} = [] }

sub get {
    my $self = shift;

    push( @{ $self->status }, 'get' );

    return $self->next::method(@_);
}

sub set {
    my $self = shift;

    push( @{ $self->status }, 'set' );

    return $self->next::method(@_);
}

sub expire {
    my $self = shift;

    push( @{ $self->status }, 'expire' );

    return $self->next::method(@_);
}

sub flush {
    my $self = shift;

    push( @{ $self->status }, 'flush' );

    return $self->next::method(@_);
}

1;
