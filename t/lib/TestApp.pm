package TestApp;
use Mojo::Base 'Mojolicious';

sub startup {
    my $app = shift;

    $app->plugin(
        XCached => [
            map {
                {
                    driver         => 'Mojo',
                    driver_options => {},
                    default_expire => $_,
                }
            } ( 1 .. 3 ),
        ]
    );

    push @{ $app->renderer->classes }, __PACKAGE__;
    push @{ $app->static->classes },   __PACKAGE__;

    my $r = $app->routes;

    $r->get('/')->to('test#index');
}

sub x3 {
    my ( $self, $num ) = @_;

    return wantarray ? ( $num * 3, 'okay' ) : ( $num * 3 );
}

1;

__DATA__

@@ test/include.html.ep

test/include <%= $rt %>

% content_for for => begin
    content_for test/include <%= $rt %>
% end

% content_with with => begin
    content_with test/include <%= $rt %>
% end

@@ test/index.html.ep
% layout 'default';

test/index <%= $t %>/<%= $rt %>

% content_for for => begin
    content_for test/index <%= $rt %>
% end

% content_with with => begin
    content_with test/index <%= $rt %>
% end

%= xcinclude 'test/include' => ( xcache_content_for => ['for'], xcache_content_with => ['with'] )

@@ layouts/default.html.ep
%= content
%= content 'for'
%= content 'with'
