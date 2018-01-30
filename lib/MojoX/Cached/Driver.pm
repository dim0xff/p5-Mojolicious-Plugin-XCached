package MojoX::Cached::Driver;

# ABSTRACT: XCached driver superclass/interface

use Mojo::Base -base;

sub get    {...}
sub set    {...}
sub expire {...}
sub flush  {...}

1;

__END__

=head1 DESCRIPTION

Use this module as base to create your own XCached drivers

Driver must support non-blocking interface, but non-blocking features
are not required. All callbacks will get driver instance as first argument.

You have to implement these methods


=method get ($key, $cb?)

Get cached value by C<$key>. On success returns HASH:

    {
        value     => ..., # cached data
        expire_at => ..., # expiration time in seconds

        # Also could contain driver specified data
        ...
    }

Optional callback C<$cb> could be added for non-blocking C<get>.

=method set ($key, $data, $expire_in?, $cb?)

Cache C<$data> by C<$key>.
Optional expiration in seconds could be set via C<$expire_in>.
On success returning HASH will be passed as argument,
otherwise - nothing (empty list)

Must return like-L</get> HASH.

Optional callback C<$cb> could be added as last argument for
non-blocking C<set>.
On success returning HASH will be passed as argument,
otherwise - nothing (empty list)

=method expire ($key, $cb?)

Expire cached data by C<$key>. Returns expire status.

Optional callback C<$cb> could be added as last argument for
non-blocking C<expire>. Expire status will be passed as argument.

=method flush($cb?)

Clear cache.

Optional callback C<$cb> could be added as last argument for
non-blocking C<flush>. Will be fired once cache is flushed.
