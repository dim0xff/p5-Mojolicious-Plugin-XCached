package TestApp::Controller::Test;
use Mojo::Base 'Mojolicious::Controller';

sub index {
    my $c = shift;

    $c->render_later;

    $c->stash( NO_XCACHED => 1 ) if $c->param('nc');

    my ( $v1, $v2 ) = $c->xcache(
        'key-req' => sub {
            return wantarray ? ( shift, shift ) : shift;
        } => [ $c->param('t'), 42 ],
        (
            driver => { t => $c->param('now') },
            fn_key => 0,
        ),
        sub {
            my ( $ca, $t ) = @_;

            $c->render(
                template => 'test/index',
                t        => $t->[0],
                rt       => $c->param('t'),
            );

            return wantarray ? ( 300, 400 ) : 300;
        }
    );
}

1;
