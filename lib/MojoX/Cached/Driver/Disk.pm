package MojoX::Cached::Driver::Disk;

# ABSTRACT: Slow XCached driver with filesystem storage

use Mojo::Base 'MojoX::Cached::Driver';

use Digest::MD5 qw(md5_hex);
use Fcntl qw(:flock);
use Mojo::File;
use Storable qw(nfreeze thaw);

has 'dir';
has 'files_mode';
has 'dir_mode';

use constant DEBUG => $ENV{MOJOX_CACHED_DEBUG};

sub new {
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    # Create dir to save files
    if ( defined( $self->dir ) && !-e $self->dir ) {
        my $dir = Mojo::File->new( $self->dir );

        $dir->make_path(
            $self->dir_mode
            ? ( { mode => $self->dir_mode } )
            : ()
        );
    }

    die 'dir is required' unless defined $self->dir && -e $self->dir;

    $self->{dir} = Mojo::File->new( $self->dir );

    return $self;
}

sub get {
    my ( $self, $key ) = @_;

    my $data = $self->_read($key) or return;

    # Expired
    if ( $data->{expire_at} && $data->{expire_at} < time ) {
        $self->expire($key);
        return;
    }

    return $data;
}

sub set {
    my ( $self, $key, $value, $expire_in ) = @_;

    my $data = {
        value     => $value,
        expire_at => $expire_in ? ( time + $expire_in ) : (undef),
    };

    $self->_write( $key => $data );

    return $data;
}

sub expire {
    my ( $self, $key ) = @_;

    return unlink $self->_file($key);
}

sub flush {
    my $self = shift;

    for my $file ( $self->dir->list_tree->each ) {
        unlink $file;
    }
}

sub _file {
    my ( $self, $key ) = @_;

    $key = md5_hex($key);

    return $self->dir->child( substr( $key, 0, 2 ), $key );
}

sub _write {
    my ( $self, $key, $data ) = @_;

    my $file = $self->_file($key);

    # Create dir if not exists
    $file->dirname->make_path(
        $self->dir_mode
        ? ( { mode => $self->dir_mode } )
        : ()
    ) unless -e $file->dirname;


    # Save data
    $data = nfreeze($data);

    my $fh;
    if ( -e $file ) {
        my $tmp = Mojo::File::tempfile;
        $tmp->spurt($data);

        $fh = $file->open('<');
        flock( $fh, LOCK_EX );
        $tmp->move_to($file);

    }
    else {
        $fh = $file->open('>');
        flock( $fh, LOCK_EX );
        $file->spurt($data);
    }

    # Set file permissions
    chmod $self->files_mode, $file if defined $self->files_mode;

    flock( $fh, LOCK_UN );
    $fh->close;

    return $file;
}

sub _read {
    my ( $self, $key ) = @_;

    my $file = $self->_file($key);

    return unless -e $file && -r $file && -f $file;

    local $@;

    my $data = eval {
        my $fh = $file->open('<');
        flock( $fh, LOCK_SH );
        my $data = $file->slurp;
        flock( $fh, LOCK_UN );

        $data = thaw($data);
    };

    warn $@ if DEBUG && $@;

    return $data;
}


1;

__END__

=head1 DESCRIPTION

Slow cache driver with filesystem storage.

It uses L<Storable> to (de-)serialize data.

=attr dir

Path to dir where cached data will be saved

    use MojoX::Cached;
    use MojoX::Cached::Driver::Dir;

    my $driver  = MojoX::Cached::Driver::Dir->new( dir => '/tmp/xcached' );
    my $xcached = MojoX::Cached->new( driver => $driver, ... );

=attr files_mode

Oct files mode (will be set via C<chmod()>) for files with cached data.

=attr dir_mode

Oct dir mode (will be set on dir creating via L<Mojo::File/make_path>
C<mode> attribute) for dirs with cache-files.
