use inc::Module::Install;

name('IO-All');
version_from('lib/IO/All.pm');
license('perl');

requires('Spiffy');

&WriteAll;
