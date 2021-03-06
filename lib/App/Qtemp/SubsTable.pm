#!/usr/bin/env perl
package App::Qtemp::SubsTable;

use strict;
use warnings;
use Data::Dumper;
use App::Qtemp::Parser;
require Exporter;
use AutoLoader qw(AUTOLOAD);
our @ISA;
push @ISA, 'Exporter';

our @EXPORT = qw{subtable_from};

use Exception::Class (
    'ValueError',
    'FileIOError',
    'SubsParseError',
    'CompiledTableError',
    'CyclicDependencies',
    'NoPatternError',
    'DupPatternError',
);

our $VERSION = '0.0_3';

use Moose;

has 'substitutions' 
    => (isa => 'HashRef', is => 'rw', default => sub { {} });
has 'is_compiled'
    => (isa => 'Bool', is => 'rw', default => 0);

# Subroutine: _order_subs_(\%visited, \%adj_verts, $source)
# Type: INSTANCE METHOD
# Purpose: 
#   Perform a depth first search and topological sort
#   Updates \%visited.
# Returns: 
#   Topological sort of vertices visited in this call.
sub _order_subs_ {
    my ($visited, $adj_verts_of, $source) = @_;

    my @order;

    return () if ($visited->{$source});
    $visited->{$source} = 1;

    for my $dest (@{$adj_verts_of->{$source}}) {
        if (!$visited->{$dest}){
            push @order, _order_subs_($visited, $adj_verts_of, $dest);
        }
        elsif ($visited->{$dest} == 1) {
            CyclicDependencies->throw(
                error => "Pattern '$dest' is involved in a cycle");
        }
        else {
            # Do nothing for cross edges.
        }
    }

    $visited->{$source} = 2;

    push @order, $source;

    return @order;
}

# Subroutine: $substable->compile()
# Type: INSTANCE METHOD
# Purpose: Compile the table so it can perform substitutions.
# Returns: Nothing.
sub compile {
    my $self = shift;
    my @patterns = keys %{$self->substitutions};
    my %deps_of;
    # Find dependencies.
    for my $p (@patterns) {
        # Handle the substitution and get its tokens.
        my $s = $self->substitutions->{$p};
        #print {\*STDERR} "Checking dependencies of '$s'.\n";
        my @dependencies = (map {($_->dependent_subs)} @{$s});

        my %s_is_dep_of;
        for my $dep (@dependencies) {
            $s_is_dep_of{$dep} = 1;
        }

        $deps_of{$p} = [keys %s_is_dep_of];
    }

    # Try to create an order for dependency fulfillment.
    my @sub_order;

    my %considered;
    # Implement a depth first search / topological ordering.
    for my $p (@patterns) {
        @sub_order = (@sub_order, _order_subs_(\%considered, \%deps_of, $p) );
    }

    # print {\*STDERR} "sub order: @sub_order\n";

    # Do substitutions in a dependency first method.
    $self->is_compiled(1);
    for my $p (@sub_order) {
        $self->substitutions->{$p} = $self->_perform_subs_($self->substitutions->{$p});
    }

    return;
}

# Subroutine: $subtable->contains($pattern)
# Type: INSTANCE METHOD
# Purpose: Check if a pattern is in the SubsTable.
# Returns: A boolean value; 
#   True iff the pattern is in the SubsTable.
sub contains {
    my ($self, $p) = @_;
    ValueError->throw("Pattern query '$p' is not defined.") if !defined $p;
    return defined $self->substitutions->{$p};
}

# Subroutine: $subtable->patterns()
# Type: INSTANCE METHOD
# Returns: A list of patterns in the SubsTable
sub patterns {
    my $self = shift;
    return keys %{$self->substitutions};
}

# Subroutine: $subtable->union($other_table)
# Type: INSTANCE METHOD
# Purpose: Union two uncompiled SubsTables
# Returns: A new SubsTables.
sub union {
    my ($self, $other) = @_;

    CompiledTableError->throw(
            error => "union() called on compiled table.\n")
        if $self->is_compiled;
    CompiledTableError->throw(
            error => "union() can't be given a compiled table.\n")
        if $other->is_compiled;

    my %s1 = %{$self->substitutions};

    for my $p (keys %s1) {
        DupPatternError->throw(error => "Key $p exists in both tables.\n")
            if $other->contains($p);
    }
    my %u = (%s1, %{$other->substitutions});

    return App::Qtemp::SubsTable->new(substitutions => \%u);
}

### INSTANCE METHOD
# Subroutine: dup
# Usage: $subtable->dup( )
# Purpose: Duplicate a subtable.
# Returns: 
#   A new App::Qtemp::SubsTable object with the same substitutions as the
#   original instance.
# Throws: Nothing
sub dup {
    my $self = shift;
    return $self->union(App::Qtemp::SubsTable->new());
}

# Subroutine: $subtable->_add_($pattern, $substitution)
# Type: INSTANCE METHOD
# Purpose: 
#   Helper method for adding substitutions.
#   Accepts a pattern and an array of parsed substitution contents.
# Returns: Nothing.
sub _add_ {
    my ($self, $patt, $sub) = @_;

    CompiledTableError->throw(
            error => "add() called on compiled table.\n")
        if $self->is_compiled;

    if ($self->contains($patt)) {
        DupPatternError->throw(
            error => "Pattern '$patt' is already defined as '$sub'.\n");
    }

    $self->substitutions->{$patt} = $sub;
}

# Subroutine: $subtable->add($pattern, $substitution)
# Type: INSTANCE METHOD
# Purpose: Add a single pattern substitution into a table.
# Returns: Nothing.
sub add {
    my ($self, $patt, $sub) = @_;

    CompiledTableError->throw(
            error => "add() called on compiled table.\n")
        if $self->is_compiled;

    ValueError->throw(error => "Pattern '$patt' is not defined.\n")
        if !defined $patt;
    ValueError->throw(error => "Substitution '$sub' is not defined.\n")
        if !defined $sub;

    if ($self->contains($patt)) {
        DupPatternError->throw(
            error => "Pattern '$patt' is already defined as '$sub'.\n");
    }

    $self->substitutions->{$patt} = parse_sub_contents($sub);
}

### INTERNAL UTILITY
# Subroutine: _perform_subs_
# Usage: $self->_perform_subs_( $token_array_ref )
# Purpose: Perform substitutions on a tokenized string.
# Returns: A Perl string, with substitutions performed.
# Throws: ValueErrors when dependency problems arise.
sub _perform_subs_ {
    my $self = shift;
    my $tokens_ref = shift;

    my $s = "";
    for my $t (@{$tokens_ref}) {
        if ($t->isa('TStr')) {
            $s .= $t->{val};
        }
        elsif ($t->isa('TSub')) {
            my $k = $t->{key};
            #print {\*STDERR} "Performing sub, $k\n";
            if ($k eq '$') {
                $s .= '$';
                next;
            }
            my $rep_str = $self->substitutions->{$k};
            if (ref $rep_str eq q{}) {
                #print {\*STDERR} "Substituting for, $rep_str\n";
                if (!defined $rep_str) {
                    NoPatternError->throw(error=>"No pattern $k defined.\n");
                }
                $s .= $rep_str;
            }
            else {
                ValueError->throw(error=>"Unexpected reference $rep_str.\n");
            }
        }
        elsif ($t->isa('TPipe')) {
            my $command = $self->_perform_subs_($t->{contents});
            my $exec_output = qx{$command};
            $exec_output =~ s/\n+\z//xms;
            $s .= $exec_output;
        }
        elsif ($t->isa('TCondSub')) {
            my $k = $t->{key};
            if ($self->contains($k)) {
                $s .= $self->_perform_subs_($t->{$t->{negated} ? 'false_contents' : 'true_contents'});
            }
            else {
                $s .= $self->_perform_subs_($t->{$t->{negated} ? 'true_contents' : 'false_contents'});
            }
        }
        else {
            ValueError->throw(error=>"Unrecognized token $t.\n");
        }
    }
    return $s;

    return;
}


# Subroutine: $sub_table->perform_subs($str)
# Type: INSTANCE METHOD
# Purpose: Perform substitutions on a given string.
# Returns: 
#   Undef if the table is not compiled.
#   A copy of the string with substitutions performed.
sub perform_subs {
    my ($self, $str) = @_;
    return if !$self->is_compiled;
    my $tokens_ref = parse_sub_contents($str);
    return $self->_perform_subs_($tokens_ref);
}

### INTERFACE SUB/INTERNAL UTILITY
# Subroutine: subtable_from_string
# Usage: subtable_from_string( $str )
# Purpose: Create a subtable from a string description.
# Returns: Nothing
# Throws: Nothing
sub subtable_from_string {
    my $subs_text = shift;
    my $subs_ref = parse_subs($subs_text);

    my %sub;
    for my $subdef (@{$subs_ref}) {
        my ($patt, $sub_contents) = ($subdef->{key}, $subdef->{contents});

        #SubsParseError->throw(error => "Can't parse subline:\n$subdef\n")
        #    if (!defined $substr);
        #print {\*STDERR} "Substitution '$patt' found; ";
        #print {\*STDERR} Dumper $sub_contents;

        $sub{$patt} = $sub_contents;
    }

    return App::Qtemp::SubsTable->new(substitutions => \%sub);
}


# Subroutine: subtable_from($filename)
# Type: INTERFACE SUB
# Purpose: Create subtable from the contents of a .subs format file.
# Returns: A new subtable.
sub subtable_from {
    my $filename = shift;

    open my $fh, "<", $filename
        or FileIOError->throw(error => "Can't open subs file $filename.");
    my $subs_text = do {local $/; <$fh>};
    close $fh;

    return subtable_from_string($subs_text);
}

return 1;

__END__

=head1 NAME

QuickTemplate::SubstitutionTable - QuickTemplate::Generator lookup tables.

=head1 VERSION

Version 0.0_1
Originally created on 04/26/10 18:49:01

=head1 DESCRIPTION

=head1 AUTHOR

Bryan Matsuo (bryan.matsuo@gmail.com)

=head1 BUGS

=over

=back

=head1 COPYRIGHT
