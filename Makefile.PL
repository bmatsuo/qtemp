use 5.008009;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'qtemp',
    VERSION_FROM      => 'scripts/qtemp', # finds $VERSION
    PREREQ_PM         => { # e.g., Module::Name => 1.1
        'Class::InsideOut'  => '0',
        'Getopt::Euclid'    => '0',
        'Readonly'          => '0',
    }, 
    EXE_FILES           => [qw{scripts/qtemp}],
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'scripts/qtemp', # retrieve abstract from module
       AUTHOR         => 'Bryan Matsuo <bryan.matsuo@gmail.com>') : ()),
);
