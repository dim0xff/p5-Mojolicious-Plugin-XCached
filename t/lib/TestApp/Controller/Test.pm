package TestApp::Controller::Test;
use Mojo::Base 'Mojolicious::Controller';

sub index {
    my $c = shift;

    $c->render_later;

    my $t = $c->xcache(
        'key-req' => sub { return shift } => [ $c->param('t') ],
        (
            fn_key => 0,
        ),
        sub {
            my ( undef, $t ) = @_;
    

            $c->render(
                t  => $t,
                rt => $c->param('t'),
            );
        }
    );
}

1;
