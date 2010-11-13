# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl QuickTemplate.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 28;
BEGIN { use_ok('App::Qtemp::Parser') };
use App::Qtemp::SubsTable;
use Data::Dumper;

#########################

my $t;

###################
# TEST SECTIONING #
###################

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

######################
# TEST SUBSTITUTIONS #
######################

my $sub_template=<<'EOT';
This is a simple $type template.
It is for ${action}.
EOT
$t = parse_template($sub_template);
ok($t->{contents}->[1]->isa('TSub'));
ok($t->{contents}->[2]->isa('TStr'));
ok($t->{contents}->[3]->isa('TSub'));

##############
# TEST PIPES #
##############

my $pipe_template=<<'EOT';
This is all the files I can see $(ls \(\))
EOT
$t = parse_template($pipe_template);
ok(scalar (@{$t->{contents}}) > 1);
#print {\*STDERR} Dumper $t->{contents};
ok($t->{contents}->[-2]->isa('TPipe'));
#print {\*STDERR} $t->{contents}->[-2]->{contents}->[0]->{val}, "\n";
ok($t->{contents}->[-2]->{contents}->[0]->{val} eq 'ls ()');

#####################
# TEST CONDITIONALS #
#####################

my $cond_template = <<'EOT';
$?DATE?{Date: $DATE}
Author: $AUTHOR
Description: $?!desc?{Place description here.}{$desc}
EOT
$t = parse_template($cond_template);
#print {\*STDERR} Dumper $t;
my $cond = $t->{contents}->[0];
ok($cond->{negated} == 0);
ok(scalar (@{$cond->{false_contents}}) == 0);
ok(scalar (@{$cond->{true_contents}}) == 2);
ok($cond->{true_contents}->[0]->isa('TStr'));
ok($cond->{true_contents}->[1]->isa('TSub'));
my $cond1 = $t->{contents}->[-2];
ok($cond1->{negated} == 1);
ok(scalar (@{$cond1->{true_contents}}) == 1);
ok(scalar (@{$cond1->{false_contents}}) == 1);
ok($cond1->{false_contents}->[0]->{key} eq 'desc');
ok($cond1->{false_contents}->[0]->isa('TSub'));

#################
# TEST Includes #
#################

my $incl_template = <<'EOT';
Want to include $[other-template FILE="\"$FILE\"" title="Template Title"]
EOT
$t = parse_template($incl_template);
my $inc = $t->{contents}->[-2];
#print {\*STDERR} Dumper $inc;
ok($inc->isa('TIncl'));
my $inc_subs = $inc->{sub_defs};
#print {\*STDERR} Dumper $inc_subs;
ok(scalar ( @{ $inc_subs } ) == 2);
ok(scalar ( @{ $inc_subs->[0]->{contents} } ) == 3);
ok($inc_subs->[0]->{contents}->[0]->{val} eq q{"});
