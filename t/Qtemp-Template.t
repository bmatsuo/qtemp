# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl QuickTemplate.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 5;
BEGIN { use_ok('App::Qtemp::Template') };
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

my $no_sub_table = App::Qtemp::SubsTable->new(substitutions => {'FILE' => 'test_file'});
my $temp = parse_template_string($t1);
ok(defined $temp->local_subs);
ok(defined $temp->templ_str);
ok(defined $temp->script);
ok($temp->subbed_script($no_sub_table) =~ m/\A \n cat \s 3 \nchmod \s [+]x \s test_file \n \n\z/xms);
