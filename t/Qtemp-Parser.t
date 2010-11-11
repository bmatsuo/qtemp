# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl QuickTemplate.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 1;
BEGIN { use_ok('App::Qtemp::Parser') };
use App::Qtemp::SubsTable;

#########################


# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.
my $t1 = <<'EOT';
x=3
!!
This file is $x.
5x
!!

cat $x
chmod +x $FILE

EOT
