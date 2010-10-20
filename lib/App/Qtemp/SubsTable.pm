#!/usr/bin/env perl

package App::Qtemp::SubsTable;

use strict;
use warnings;
use Carp;

use Exception::Class (
    'ValueError',
    'InvalidTokenError',
    'FileIOError',
    'SubsParseError',
    'CompiledTableError',
    'CyclicDependencies',
    'NoPatternError',
    'DupPatternError',
);

use App::Qtemp::QuickTemplate;

our $VERSION = '0.01';

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
            CyclicDependencies->throw("Pattern $dest is involved in a cycle");
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
    ValueError->throw("Pattern query is not defined.") if !defined $p;
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

    CompiledTableError->throw(error => "Can't union a compiled table")
        if ($self->is_compiled || $other->is_compiled);

    my %s1 = %{$self->substitutions};

    for my $p (keys %s1) {
        DupPatternError->throw(error => "Tables intersect at key $p. ")
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

    ValueError->throw(error => "Pattern is not defined. ")
        if !defined $patt;
    ValueError->throw(error => "Substitution is not defined. ")
        if !defined $sub;

    if ($self->contains($patt)) {
        DupPatternError->throw(error => "Pattern $patt is in the SubsTable already. ");
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

    my $dollar = '$';

    DOSUBSTITUTION:
    for my $t ($self->_tokenize_($str)) {
        if ($t eq q{}) { 
            # print {\*STDERR} "EMPTY TOKEN\n";
            next DOSUBSTITUTION; 
        }
        if ($t !~ m/\A \$ /xms) { 
            # The token does not need substitution.
            # print {\*STDERR} "NO SUB TOKEN $t\n";
            push @subbed, $t;
            next DOSUBSTITUTION; }
        if ($t =~ s/\A \${2} \z/\$/xms) { 
            # print {\*STDERR} "DOLLAR SIGN SUB $t\n";
            push @subbed, '$';
            next DOSUBSTITUTION; }

        # THIS IS NOT WORKING WITH A 'gc' FLAG ON THE REGEX!!!
        my $pattern;
        # Standard variable substitution
        if ($t =~ m/\A \$ (\w+) \z/xms) {
            # print {\*STDERR} "STANDARD SUB $t\n";
            $pattern = $1;
            NoPatternError->throw(error => "Couldn't find pattern $pattern.")
                if !$self->contains($pattern);
            push @subbed, $self->substitutions->{$pattern};
        }
        # Brace quoted variable substitutions (not space delimited).
        elsif ($t =~ m/\A \$ [{] ( [^{}]* | \\ [{}] ) [}] \z/xms) {
            # print {\*STDERR} "QUOTED SUB $t\n";
            $pattern = $1;
            NoPatternError->throw(error => "Couldn't find pattern $pattern.")
                if !$self->contains($pattern);
            push @subbed, $self->substitutions->{$pattern};
        }
        # System command substiution (after substituting on strings).
        elsif ($t =~ m/\A \$ [(] ( [^()]* | \\ [()] ) [)] \z/xms) {
            # print {\*STDERR} "SYSTEM SUB $t\n";
            $pattern = $1;
            my $x = $self->perform_subs($pattern);
            push @subbed, qx{$x};
            # TODO: Check exitcode of backtick system call.
        }
        else { 
            croak("Unexpected token $t encounted during substitutions.");
        }
    }
    return (join q{}, @subbed);
}

# Subroutine: $substable->_tokenize_($str)
# Type: INSTANCE METHOD
# Returns: Return the token of $str for parsing and compiling.
sub _tokenize_ {
    my ($self, $str) = @_;
    my @tokens;
    my $dollar = '$';
    TOKENIZE:
    while (1) {
        if ($str =~ m/\G ([^$dollar]*) \${2} /gcxms) { 
            push @tokens, $1 if $1;
            push @tokens, '$$';
            # print {\*STDERR} "DOUBLE DOLLAR\n";
            next TOKENIZE; 
        }

        if ($str =~ m/\G ([^$dollar]* ' (?: [^'] | \\ [']) ')/gcxms) { 
            push @tokens, $1;
            # print {\*STDERR} "SINGLE QUOTE\n";
            next TOKENIZE; 
        }

        if ($str =~ m/\G ([^$dollar]+) /gcxms) {
            push @tokens, $1;
            # print {\*STDERR} "NOTHING\n";
            next TOKENIZE;
        }


        my $pattern;
        # Standard variable substitution
        if ($str =~ m/\G (\$ \w+) /gcxms) {
            # print {\*STDERR} "STANDARD\n";
            push @tokens, $1;
        }
        # Brace quoted variable substitutions (not space delimited).
        elsif ($str =~ m/\G ( \$ [{] (?: [^{}] | \\ [{}] )* [}] ) /gcxms) {
            # print {\*STDERR} "QUOTED\n";
            push @tokens, $1;
        }
        # System command substiution (after substituting on strings).
        elsif ($str =~ m/\G ( \$ [(] (?: [^()] | \\ [()] )* [)] )/gcxms) {
            # print {\*STDERR} "SYSTEM\n";
            push @tokens, $1;
        }
        elsif ($str =~ m/\G (\$ \W)/gcxms) {
            InvalidTokenError->throw(error => "Invalid token $1 found.");
        }
        # Just chew up the rest of the string
        elsif ($str =~ m/\G (.+) \z/gcxms) {
            # print {\*STDERR} "ELSE\n";
            push @tokens, $1;
        }
        else {
            # We must be at the end of the string.
            last TOKENIZE;
        }
    }
    return @tokens;
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
    for my $i (0 .. @lines) {
        my $sub_line = $lines[$i];
        $sub_line = $prepend . $sub_line if defined $prepend;
        $prepend = undef;
        if ($sub_line =~ s/\\ \n \z/\n/xms) {
            $prepend = $sub_line ;
        }
        else {
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
