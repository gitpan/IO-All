package IO::All::Dir;
use strict;
use warnings;
use IO::All '-Base';
use mixin 'IO::All::Filesys';
use IO::Dir;

#===============================================================================
const type => 'dir';
option 'sort' => 1;
chain filter => undef;
option 'deep';

#===============================================================================
sub dir {
    bless $self, __PACKAGE__;
    $self->name(shift) if @_;
    return $self->_init;
}

sub dir_handle {
    bless $self, __PACKAGE__;
    $self->_handle(shift) if @_;
    return $self->_init;
}

#===============================================================================
sub assert_open {
    return if $self->is_open;
    $self->open;
}

sub open {
    $self->is_open(1);
    $self->assert_dirpath($self->name)
      if $self->name and $self->_assert;
    my $handle = IO::Dir->new;
    $self->io_handle($handle);
    $handle->open($self->name)
      or $self->throw($self->open_msg);
    return $self;
}

sub open_msg {
    my $name = defined $self->name
      ? " '" . $self->name . "'"
      : '';
    return qq{Can't open directory$name:\n$!};
}

#===============================================================================
sub All {
    $self->all(0);
}

sub all {
    my $depth = @_ ? shift(@_) : $self->_deep ? 0 : 1;
    my $first = not @_;
    my @all;
    while (my $io = $self->next) {
        push @all, $io;
        push(@all, $io->all($depth - 1, 1))
          if $depth != 1 and $io->is_dir;
    }
    @all = grep {&{$self->filter}} @all
      if $self->filter;
    return @all unless $first and $self->_sort;
    return sort {$a->name cmp $b->name} @all;
}

sub All_Dirs {
    $self->all_dirs(0);
}

sub all_dirs {
    grep {$_->is_dir} $self->all(@_);
}

sub All_Files {
    $self->all_files(0);
}

sub all_files {
    grep {$_->is_file} $self->all(@_);
}

sub All_Links {
    $self->all_links(0);
}

sub all_links {
    grep {$_->is_link} $self->all(@_);
}

sub empty {
    my @all = $self->all;
    not @all;
}

sub next {
    $self->assert_open;
    my $name = '.'; 
    while ($name =~ /^\.{1,2}$/) {
        $name = $self->io_handle->read;
        unless (defined $name) {
            $self->close;
            return;
        }
    }
    return IO::All->new(File::Spec->catfile($self->name, $name));
}

sub mkdir {
    defined($self->perms)
    ? CORE::mkdir($self->name, $self->perms)
    : CORE::mkdir($self->name);
    return $self;
}

sub mkpath {
    require File::Path;
    File::Path::mkpath($self->name, @_);
    return $self;
}

sub rmdir {
    rmdir $self->name;
}

sub rmtree {
    require File::Path;
    File::Path::rmtree($self->name, @_);
}

#===============================================================================
sub overload_table {
    (
        '@{} dir' => 'overload_as_array',
        '%{} dir' => 'overload_as_hash',
    )
}

sub overload_as_array() {
    [ $_[1]->all ];
}

sub overload_as_hash() {
    +{ 
        map {
            (my $name = $_->name) =~ s/.*[\/\\]//;
            ($name, $_);
        } $_[1]->all 
    };
}

1;

__DATA__

=head1 NAME 

IO::All::Dir - Directory Support for IO::All

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
