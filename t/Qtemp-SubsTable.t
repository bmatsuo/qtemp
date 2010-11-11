# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as 
# `perl QuickTemplate-Generator.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 7;
BEGIN { use_ok('App::Qtemp::SubsTable') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $st = App::Qtemp::SubsTable->new(substitutions => {
    "FOO" => [bless ({val => "foo"},'TStr')],
    "bar" => [bless ({val => "baz"},'TStr')],});

#print {\*STDERR} map {"'$_'"} @tokens;
#print {\*STDERR} "\n";

ok($st->contains('bar'));
my @patts = sort $st->patterns;
ok($patts[0] eq 'FOO' && $patts[1] eq 'bar');

#my $st2 = App::Qtemp::SubsTable->new(substitutions => {
#    "x" => "y",
#    "qux" => '$x, $bar $(bash -c "echo -n \"${FOO} ()\"")',});
my $st2 = App::Qtemp::SubsTable::subtable_from_string(<<'EOTABLE'
x="y"
qux="$x, $bar $(bash -c 'echo $FOO,') "
EOTABLE
);

my $st3 = $st->union($st2);
ok($st3->contains('x'));
ok($st3->contains('bar'));
ok(!defined $st3->compile());

my $s = $st3->_perform_subs_([bless ({key => 'qux'}, 'TSub'), bless ({key => 'x'}, 'TSub')]);
#print {\*STDERR} "subbed: $s\n";
ok($s eq "y, baz foo, y");
