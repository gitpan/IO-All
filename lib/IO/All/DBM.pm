package IO::All::DBM;
use strict;
use warnings;
use IO::All::File '-Base';
use Fcntl;

field _dbm_list => [];
field '_dbm_class';
field _dbm_extra => [];

sub dbm {
    bless $self, __PACKAGE__;
    $self->_dbm_list([@_]);
    return $self;
}

sub assert_open {
    return $self->tied_file 
      if $self->tied_file;
    $self->open;
}

sub open {
    $self->is_open(1);
    return $self->tied_file if $self->tied_file;
    $self->assert_filepath if $self->_assert;
    my $dbm_list = $self->_dbm_list;
    my @dbm_list = @$dbm_list ? @$dbm_list :
      (qw(DB_File GDBM_File NDBM_File ODBM_File SDBM_File));
    my $dbm_class;
    for my $module (@dbm_list) {
        if (defined $INC{"$module.pm"} || eval "eval 'use $module; 1'") {
            $self->_dbm_class($module);
            last;
        }
    }
    $self->throw("No module available for IO::All DBM operation")
      unless defined $self->_dbm_class;
    my $mode = $self->_rdonly ? O_RDONLY : O_RDWR;
    if ($self->_dbm_class eq 'DB_File::Lock') {
        my $type = eval '$DB_HASH' or die; die $@ if $@;
        my $flag = $self->_rdwr ? 'write' : 'read';
        $mode = $self->_rdwr ? O_RDWR : O_RDONLY;
        $self->_dbm_extra([$type, $flag]);
    }
    $mode |= O_CREAT if $mode & O_RDWR;
    $self->mode($mode);
    $self->perms(0666) unless defined $self->perms;
    return $self->tie_dbm;
}

sub tie_dbm {
    my $hash;
    my $filename = $self->name;
    tie %$hash, $self->_dbm_class, $filename, $self->mode, $self->perms, 
        @{$self->_dbm_extra}
      or $self->throw("Can't open '$filename' as DBM file:\n$!");
    $self->tied_file($hash);
}

1;

__DATA__

=head1 NAME 

IO::All::DBM - DBM Support for IO::All

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
