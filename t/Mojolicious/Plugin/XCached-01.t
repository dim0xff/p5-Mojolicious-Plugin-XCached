use Mojo::Base -strict;

use lib 't/lib';

use Test::More;
use Test::Mojo;

my $t = Test::Mojo->new('TestApp');

my $r = $t->get_ok('/?t=1')->status_is(200);
$r->content_like(
    qr|
        test/index\s1/1
        \s+
        test/include\s1
        \s+
        content_for\stest/index\s1
        \s+
        content_for\stest/include\s1
        \s+
        content_with\stest/include\s1
    |x
);

sleep 2;

$r = $t->get_ok('/?t=2')->status_is(200);
$r->content_like(
    qr|
        test/index\s1/2
        \s+
        test/include\s1
        \s+
        content_for\stest/index\s2
        \s+
        content_for\stest/include\s1
        \s+
        content_with\stest/include\s1
    |x
);

done_testing();
