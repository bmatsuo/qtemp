# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl QuickTemplate.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 11;
BEGIN { use_ok('App::Qtemp::Parser') };
use App::Qtemp::SubsTable;
use Data::Dumper;

#########################

my $t;
my $one_section_templ=<<'EOT';
This section only has a content section.
EOT
$t = parse_template($one_section_templ);
ok(scalar (@{$t->{sub_defs}}) == 0);
ok(scalar (@{$t->{contents}}) == 1);

my $two_section_templ=<<'EOT';
sub="A two section template."
x="Another substitution."
!!
This is $sub
EOT
$t = parse_template($two_section_templ);
ok(scalar (@{$t->{sub_defs}}) == 2);
ok(scalar (@{$t->{contents}}) == 3);

my $three_section_templ=<<'EOT';
x="y"
z="$x"
!!
$FILE is $z
!!
chmod o+r $FILE
EOT
$t = parse_template($three_section_templ);
ok(scalar (@{$t->{sub_defs}}) == 2);
#print {\*STDERR} Dumper $t;
ok(scalar (@{$t->{contents}}) == 3);
#ok($t->{contents}->[3]->isa('TSTerm'));
ok(scalar (@{$t->{script}}) == 3);

my $sub_template=<<'EOT';
This is a simple $type template.
It is for ${action}.
EOT
$t = parse_template($sub_template);
ok($t->{contents}->[1]->isa('TSub'));
ok($t->{contents}->[2]->isa('TStr'));
ok($t->{contents}->[3]->isa('TSub'));

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
