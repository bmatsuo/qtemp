#!/usr/bin/env perl

package App::Qtemp::Template;

use strict;
use warnings;
use Carp;
require Exporter;
use AutoLoader qw(AUTOLOAD);
our @ISA;
push @ISA, 'Exporter';

use App::Qtemp::SubsTable;

use Exception::Class (
    'TemplateOpenError',
    'TemplateFormatError',
    'TemplateScriptError',
);

our $VERSION = '0.0_1';
our @EXPORT = qw{read_template_file parse_template_string};
use Moose;

has 'local_subs' 
    => (isa => 'App::Qtemp::SubsTable', is => 'rw', default => sub { {} });
has 'templ_str'
    => (isa => 'Str', is => 'rw', required => 1);
has 'script'
    => (isa => 'Str', is => 'rw', default => q{});

# Subroutine: read_template_file($filename)
# Type: INTERFACE SUB
# Purpose: Read a .qtemp format file.
# Returns: A new App::Qtemp::Template object.
sub read_template_file {
    my $file = shift;

    # Slurp the file.
    open my $fh, '<', $file
        or TemplateOpenError->throw(
            error => "Can't open template $file.\n");
    my $qtemp_cont = do {local $/; <$fh> };
    close $fh;

    return parse_template_string($qtemp_cont);
}

# Subroutine: parse_template_string($str)
# Type: INTERFACE SUB
# Purpose: Read a string that has the format of a .qtemp file.
# Returns: A new App::Qtemp::Template object.
sub parse_template_string {
    my $str = shift;

    # Divide the string into sections.
    my @sections = split "\n!!\n", $str;
    my $num_sections = scalar @sections;
    if (@sections > 3) {
        TemplateFormatError->throw(
            error => "Found $num_sections sections; expects no more than 3.\n");
    }

    my %templ = (
        local_subs => App::Qtemp::SubsTable->new(),
        templ_str => q{},
        script => q{},);

    # Handle the local substitution definitions if there are any.
    if ($num_sections == 3) {
        my $subs_section = shift @sections;
        my @sub_defs = split "\n", $subs_section;

        # Create a substitution hash.
        my %sub;
        my $prepend;
        for my $sub_line (@sub_defs) {
            if (defined $prepend) { $sub_line = $prepend.$sub_line; }

            if ($sub_line =~ m/ \\ \z/xms) {
                $prepend = "$sub_line\n";
                next;
            }
            else {
                $prepend = undef;
                my ($patt, $sub) = split "=", $sub_line, 2;
                if (!defined $sub) {
                    TemplateFormatError->throw(
                        error => "Malformed substitution $sub_line"
                            . "(perhaps missing '='?).\n");
                }
                $sub{$patt} = $sub
            }
        }

        # Create a SubsTable with local substitutions.
        my $sub_table = App::Qtemp::SubsTable->new(substitutions => \%sub);
        $templ{local_subs} = $sub_table;
    }

    # Handle the template section.
    my $template_section = shift @sections;
    $template_section .= "\n";
    $templ{templ_str} = $template_section;

    # Handle the script template, if one exists.
    if ($num_sections > 1) {
        my $script_templ_section= shift @sections;
        $templ{script} = $script_templ_section;
    }

    return App::Qtemp::Template->new(%templ);
}

# Subroutine: $template->subbed_template($subs_table)
# Type: INSTANCE METHOD
# Purpose: 
#   Perform substitutions on the template string.
#   Using the substitution library $subs_table (App::Qtemp::SubsTable),
#       and the local substution table.
#   $sub_table must be uncompiled (is this necessary?).
# Returns: A copy of the template string with substitutions performed.
sub subbed_template {
    my $self = shift;

    my $subs_table = shift;
    my $total_subs 
        = defined $subs_table ? $self->local_subs->union($subs_table)
        : $self->local_subs;
    $total_subs->compile;

    return $total_subs->perform_subs($self->templ_str);
}

# Subroutine: $template->subbed_script($subs_table)
# Type: INSTANCE METHOD
# Purpose: 
#   Perform substitutions on the script.
#   Using the substitution library $subs_table (App::Qtemp::SubsTable),
#       and the local substution table.
#   $sub_table must be uncompiled (Is this necessary? Maybe it SHOULD be compiled).
# Returns: A copy of the script with substitutions performed.
sub subbed_script {
    my $self = shift;

    my $subs_table = shift;
    my $total_subs 
        = defined $subs_table ? $self->local_subs->union($subs_table) 
        : $self->local_subs;
    $total_subs->compile;

    my $script = $self->script;
    $script = q{} if !defined $script;

    return $total_subs->perform_subs($script);
}

# Subroutine: $template->write_subbed($subs_table [, $filename])
# Type: INSTANCE METHOD
# Purpose: Write the subbed template to a file and execute the script.
#   Writes to standard output if a filename is not given.
# Returns: Nothing.
sub write_subbed {
    my ($self, $subs_table, $filename) = @_;

    my $file = \*STDOUT;
    my $output_is_file = defined $filename;
    if ($output_is_file) {
        # Open the destination file for writing.
        open $file, ">", $filename or TemplateOpenError->throw(
                error => "Can't open $filename for writing.\n");

        # Add a filename substitution into the SubsTable.
        $subs_table->add("FILE", $filename);
    }

    print {$file} $self->subbed_template($subs_table);

    # Attempt to execute the template's script if writing to a file.
    if ($output_is_file) {
        my $script = $self->subbed_script($subs_table);
        if (!defined $script && defined $self->script) {
            TemplateScriptError->throw(
                error => "Substitution on script returned undefined value.\n");
        }
        my @cmds = split "\n", $script;
        @cmds = grep { $_ !~ m/\A \s* \z/xms } @cmds;
        for my $cmd (@cmds) {
            print "$cmd\n";
            if (system($cmd) != 0) {
                TemplateScriptError->throw(
                    error => "Error running template script; $?\n");
            }
        }
    }
    else {
        # print {\*STDERR} "Not performing script...\n";
    }

    return;
}

return 1;

__END__
=head1 NAME

QuickTemplate - simple object describing a template file

=head1 VERSION

Version 0.0_1
Originally created on 04/26/10 18:49:01

=head1 ABSTRACT

QuickTemplate is a class and fileformat for specifying template files and
common tasks that go into producing them (think chmod +x)

=head1 DESCRIPTION

=head1 AUTHOR

Bryan Matsuo (bryan.matsuo@gmail.com)

=head1 BUGS

=over

=back

=head1 COPYRIGHT

=cut
