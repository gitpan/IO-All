use strict;
use Test::More;
use IO::All;
use lib 't';
use IO_All_Test;

my @lines = read_file_lines('t/mystuff');
plan(tests => 1 + @lines + 1);

my $io = io(-tie => 't/mystuff');
is($io->autoclose(0), 0);
while (<$io>) {
    is($_, shift @lines);
}
ok(close $io);
