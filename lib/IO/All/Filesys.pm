package IO::All::Filesys;
use warnings;
use strict;
use Spiffy '-selfless';
use Fcntl qw(:flock);

sub exists { -e $self->name }

sub filename {
    my $filename;
    (undef, undef, $filename) = $self->splitpath;
    return $filename;
}

sub is_executable { -x $self->name }
sub is_readable { -r $self->name }
sub is_writable { -w $self->name }

sub rename {
    my $new = shift;
    rename($self->name, "$new")
      ? UNIVERSAL::isa($new, 'IO::All')
        ? $new
        : $self->new($new)
      : undef;
}

sub set_lock {
    return unless $self->_lock;
    my $io_handle = $self->io_handle;
    my $flag = $self->mode =~ /^>>?$/
    ? LOCK_EX
    : LOCK_SH;
    flock $io_handle, $flag;
}

sub touch {
    $self->utime;
}

sub unlock {
    flock $self->io_handle, LOCK_UN
      if $self->_lock;
}

sub utime {
    my $atime = shift;
    my $mtime = shift;
    $atime = time unless defined $atime;
    $mtime = $atime unless defined $mtime;
    utime($atime, $mtime, $self->name);
    return $self;
}

1;

__DATA__

=head1 NAME 

IO::All::Filesys - File System Methods Mixin for IO::All

=head1 SYNOPSIS

See L<IO::All>.

=head1 DESCRIPTION

=head1 AUTHOR

Brian Ingerson <INGY@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2004. Brian Ingerson. All rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut
