use inc::Module::Install;

name('IO-All');
author('Brian Ingerson <ingy@cpan.org>');
abstract('IO::All of it to Graham and Damian');
license('perl');
version_from('lib/IO/All.pm');

requires(qw(
    perl 5.6.1
    Spiffy 0.11
    IO::String 1.04
));

&WriteAll();
