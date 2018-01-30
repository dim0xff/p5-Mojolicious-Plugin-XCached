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

You have to implement these methods


=method get ($key)

Get cached value by C<$key>. On success returns HASH:

    {
        value     => ..., # cached data
        expire_at => ..., # expiration time in seconds

        # Also could contain driver specified data
        ...
    }


=method set ($key, $data, $expire_in?)

Cache C<$data> by C<$key>.
Optional expiration in seconds could be set via C<$expire_in>.

Must return like-L</get> HASH.


=method expire ($key)

Expire cached data by C<$key>.


=method flush()

Clear cache.
