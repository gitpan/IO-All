package IO_All_Test;
use File::Path;
@EXPORT = qw(
    test_file_contents 
    test_file_contents2 
    test_matching_files
    read_file_lines
);
use strict;
use base 'Exporter';
use Test::More ();

sub test_file_contents {
    my ($data, $file) = @_;
    Test::More::is($data, read_file($file));
}

sub test_file_contents2 {
    my ($file, $data) = @_;
    Test::More::is(read_file($file), $data);
}

sub test_matching_files {
    my ($file1, $file2) = @_;
    Test::More::is(read_file($file1), read_file($file2));
}

sub read_file {
    my ($file) = @_;
    local(*FILE, $/);
    open FILE, $file 
      or die "Can't open $file for input:\n$!";
    <FILE>;
}

sub read_file_lines {
    my ($file) = @_;
    local(*FILE);
    open FILE, $file or die $!;
    (<FILE>);
}

BEGIN {
    File::Path::rmtree('t/output');
    File::Path::mkpath('t/output');
}

1;
