package IO::All::Filesys;
use warnings;
use strict;
use Spiffy qw(-selfless);  # XXX (super); needs fixing in Spiffy
use Fcntl qw(:flock);

sub absolute {
    $self->pathname(File::Spec->rel2abs($self->pathname))
      unless $self->is_absolute;
    $self->is_absolute(1);
    return $self;
}

sub exists { -e $self->name }

sub filename {
    my $filename;
    (undef, undef, $filename) = $self->splitpath;
    return $filename;
}

sub is_absolute {
    return *$self->{is_absolute} = shift if @_;
    return *$self->{is_absolute} 
      if defined *$self->{is_absolute};
    *$self->{is_absolute} = IO::All::is_absolute($self) ? 1 : 0;
}

sub is_executable { -x $self->name }
sub is_readable { -r $self->name }
sub is_writable { -w $self->name }

sub pathname {
    return *$self->{pathname} = shift if @_;
    return *$self->{pathname} if defined *$self->{pathname};
    return $self->name;
}

sub relative {
    $self->pathname(File::Spec->abs2rel($self->pathname))
      if $self->is_absolute;
    $self->is_absolute(0);
    return $self;
}

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

sub stat {
    return IO::All::stat($self, @_)  # XXX super not working :\
      if $self->is_open;
      CORE::stat($self->pathname);
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
