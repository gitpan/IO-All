use strict;
use Test::More tests => 9;
use IO::All;
use lib 't';
use IO_All_Test;

# Print name and first line of all files in a directory
my $dir = io('t/mydir'); 
ok($dir->is_dir);
while (my $io = $dir->next) {
    if ($io->is_file) {
        my $line = $io->name . ' - ' . $io->getline;
        is($line, <DATA>);
    }
}

# Print name of all files recursively
is("$_\n", <DATA>)
  for io('t/mydir')->all_files('-r');

__END__
t/mydir/file1 - file1 is fun
t/mydir/file2 - file2 is woohoo
t/mydir/file3 - file3 is whee
t/mydir/dir1/file1
t/mydir/dir2/file1
t/mydir/file1
t/mydir/file2
t/mydir/file3
