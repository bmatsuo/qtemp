#!/usr/bin/env perl

package App::Qtemp::Token;
use Moose;

has 'val' => (isa => 'Str', is => 'rw', default => q{});

package App::Qtemp::Token::String;
use Moose;
extends 'App::Qtemp::Token';

package App::Qtemp::Token::Sub;
use Moose;
extends 'App::Qtemp::Token';

#TODO: Let 'key' be given as an alternate argument to 'val'

sub key {
    my $self = shift;
    my $k = shift;
    if ($k) {
        $self->val($k);
        return;
    }
    return $self->val;
}

package App::Qtemp::Token::SPipe;
use Moose;
extends 'App::Qtemp::Token';

#TODO: Let 'call' be given as an alternate argument to 'val'
sub call {
    my $self = shift;
    my $c = shift;
    if ($c) {
        $self->val($c);
        return;
    }
    return $self->val;
}

package App::Qtemp::Token::Import;
use Moose;
extends 'App::Qtemp::Token';

sub filename {
    my $self = shift;
    my $f = shift;
    if ($f) {
        $self->val($f);
        return
    }
    return $self->val;
}

package App::Qtemp::SubsTable;

use strict;
use warnings;
require Exporter;
use AutoLoader qw(AUTOLOAD);
our @ISA;
push @ISA, 'Exporter';

our @EXPORT = qw{subtable_from};

use Exception::Class (
    'ValueError',
    'InvalidTokenError',
    'FileIOError',
    'SubsParseError',
    'UnexpectedTokenError',
    'CompiledTableError',
    'CyclicDependencies',
    'NoPatternError',
    'DupPatternError',
);

our $VERSION = '0.0_3';

use Moose;

has 'substitutions' 
    => (isa => 'HashRef[Str]', is => 'rw', default => sub { {} });
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
        my @s_tokens = $self->_tokenize_($s);
        
        my @simple_deps = map {m/\A \$ (\w+)/xms ? ($1) : ()} @s_tokens;
        my @quoted_deps = map {m/\A \$ [{] ([^}]+) [}]/xms ? ($1) : ()} @s_tokens;
        my %s_is_dep_of;
        for my $dep (@simple_deps, @quoted_deps) {
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
        $self->substitutions->{$p} = $self->perform_subs($self->substitutions->{$p});
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

# Subroutine: $subtable->add($pattern, $substitution)
# Type: INSTANCE METHOD
# Purpose: Add a single pattern substitution into a table.
# Returns: Nothing.
sub add {
    my ($self, $patt, $sub) = @_;

    ValueError->throw(error => "Pattern '$patt' is not defined.\n")
        if !defined $patt;
    ValueError->throw(error => "Substitution '$sub' is not defined.\n")
        if !defined $sub;

    if ($self->contains($patt)) {
        DupPatternError->throw(
            error => "Pattern '$patt' is already defined as '$sub'.\n");
    }

    $self->substitutions->{$patt} = $sub;

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

    my @subbed;
    return if !$self->is_compiled;

    my $pattern;
    my $dollar = '$';

    DOSUBSTITUTION:
    for my $t ($self->_tokenize_($str)) {
        if (!$t->isa('App::Qtemp::Token')) {
            ValueError->throw(val => "Non-Token object found in token list. $t\n");
        }
        elsif ($t->isa('App::Qtemp::Token::String')) {
            push @subbed, $t->val;
        }
        elsif ($t->isa('App::Qtemp::Token::Sub')) {
            if ($t->val eq '$') {
                push @subbed, $t->val;
            }
            else {
                $pattern = $t->val;
                NoPatternError->throw(error => "Pattern '$pattern' not found.")
                    if !$self->contains($pattern);
                push @subbed, $self->substitutions->{$pattern};
            }
        }
        elsif ($t->isa('App::Qtemp::Token::SPipe')) {
            $pattern = $t->val;
            my $x = $self->perform_subs($pattern);
            my $exec_output = qx{$x};
            $exec_output =~ s/\n+\z//xms;
            push @subbed, $exec_output;
            # TODO: Check exitcode of backtick system call.
        }
        else { 
            UnexpectedTokenError->throw(
                error => "Unexpected token $t encounted during substitutions.");
        }
    }
    return (join q{}, @subbed);
}

# Subroutine: $substable->_tokenize_($str)
# Type: INSTANCE METHOD
# Returns: Return the token of $str for parsing and compiling.
sub _tokenize_ {
    my ($self, $str) = @_;
    my @token_objs;
    my @tokens;
    my $dollar = '$';
    TOKENIZE:
    while (1) {
        if ($str =~ m/\G ([^$dollar']*) ' ((?: [^'] | \\ ['])*) '/gcxms) { 
            push @token_objs, App::Qtemp::Token::String->new(val => $1) if $1;
            push @token_objs, App::Qtemp::Token::String->new(val => $2) if $2;
            # print {\*STDERR} "SINGLE QUOTE\n";
            next TOKENIZE; 
        }
        if ($str =~ m/\G ([^$dollar']*) ' ((?: [^'] | \\ ['])*) \z/gcxms) { 
            # print {\*STDERR} "UNMATCHED SINGLE QUOTE\n";
            SubsParseError->throw(error => qq{Unmatched single quote ' after\n"$1'$2"});
            next TOKENIZE; 
        }
        
        if ($str =~ m/\G ([^$dollar]*) \${2} /gcxms) { 
            push @token_objs, App::Qtemp::Token::String->new(val => $1) if $1;
            push @token_objs, App::Qtemp::Token::Sub->new(val => '$');
            # print {\*STDERR} "DOUBLE DOLLAR\n";
            next TOKENIZE; 
        }

        if ($str =~ m/\G ([^$dollar]+) /gcxms) {
            push @token_objs, App::Qtemp::Token::String->new(val => $1) if $1;
            # print {\*STDERR} "NOTHING\n";
            next TOKENIZE;
        }


        my $pattern;
        my $must_match = 0;
        my $big_token = "";
        # Standard variable substitution
        if ($str =~ m/\G \$ (\w+) /gcxms) {
            # print {\*STDERR} "STANDARD\n";
            push @token_objs, App::Qtemp::Token::Sub->new(val => $1);
        }
        # Brace quoted variable substitutions (not space delimited).
        elsif ($str =~ m/\G \$ [{] ( (?: [^}] | \\ [}] )* ) [}] /gcxms) {
            # print {\*STDERR} "QUOTED\n";
            push @token_objs, App::Qtemp::Token::Sub->new(val => $1);
        }
        # System command substiution (after substituting on strings).
        elsif ($str =~ m/\G \$ [(] /gcxms) {
            # print {\*STDERR} "SYSTEM\n";
            $must_match = 1;
            $big_token = q{};
            # Parens must be balanced or otherwise escaped
            while ($must_match > 0) {
                my $add_to_token = "";
                if ($str =~ m/\G \z/gcxms) {
                    SubsParseError->throw(error => "Unterminated '('.\n");
                }
                elsif ($str =~ m/\G ([^()]*) /gcxms) {
                    $add_to_token .= $1;
                }
                elsif ($str =~ m/\G \\ ([()]) /xms) {
                    $add_to_token .= $1;
                }
                elsif ($str =~ m/\G [(]/gcxms) {
                    ++$must_match;
                    $add_to_token .= '(';
                }
                elsif ($str =~ m/\G [)]/gcxms) {
                    --$must_match;
                    $add_to_token .= ')' if $must_match > 0;
                }
                else {
                    SubsParseError->throw(error => "Error parsing '$big_token...'.\n");
                }
                $big_token .= $add_to_token;
            }
            push @token_objs, App::Qtemp::Token::SPipe->new(val => $big_token);
        }
        elsif ($str =~ m/\G \$ (\W)/gcxms) {
            InvalidTokenError->throw(error => "Invalid token $1 found.");
        }
        # Just chew up the rest of the string
        elsif ($str =~ m/\G (.+) \z/gcxms) {
            # print {\*STDERR} "ELSE\n";
            push @tokens, $1;
            push @token_objs, App::Qtemp::Token::String->new(val => $1);
        }
        else {
            # We must be at the end of the string.
            last TOKENIZE;
        }
    }
    return @token_objs;
}

# Subroutine: subtable_from($filename)
# Type: INTERFACE SUB
# Purpose: Create subtable from the contents of a .subs format file.
# Returns: A new subtable.
sub subtable_from {
    my $filename = shift;
    open my $fh, "<", $filename
        or FileIOError->throw(error => "Can't open subs file $filename.");
    my @lines = <$fh>;
    my @joined;
    my $prepend;
    for my $i (0 .. scalar @lines) {
        my $sub_line = $lines[$i];
        next if !defined $sub_line || $sub_line =~ /\A \s* \z/xms;
        $sub_line = $prepend . $sub_line if defined $prepend;
        $prepend = undef;
        if ($sub_line =~ s/\\ \n \z/\n/xms) {
            $prepend = $sub_line ;
        }
        else {
            chomp $sub_line;
            push @joined, $sub_line;
        }
    }

    my %sub;
    for my $subdef (@joined) {
        my ($patt, $substr) = split '=', $subdef, 2;

        SubsParseError->throw(error => "Can't parse subline:\n$subdef\n")
            if (!defined $substr);

        $sub{$patt} = $substr;
    }

    return App::Qtemp::SubsTable->new(substitutions => \%sub);
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
