use strict;
use lib 't', 'lib';
use Test::More tests => 5;
use IO_Dumper;
use IO_All_Test;

my $hash = {
    red => 'square',
    yellow => 'circle',
    pink => 'triangle',
};

my $io = io('t/dump2')->dump($hash);
ok(-f 't/dump2');
ok($io->close);
ok(-s 't/dump2');
test_file_contents2('t/dump2', join '', <DATA>);
ok($io->unlink);

package main;
__END__
$VAR1 = {
  'pink' => 'triangle',
  'red' => 'square',
  'yellow' => 'circle'
};
