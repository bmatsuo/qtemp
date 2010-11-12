#!/usr/bin/env perl

# Use perldoc or option --man to read documentation
package App::Qtemp::Library;

use strict;
use warnings;
use Carp;
use File::Basename;
use App::Qtemp::DirUtils;
use App::Qtemp::Parser;
use App::Qtemp::Template;
use App::Qtemp::SubsTable;

use Exception::Class (
    'UnknownTemplateException',
    'AmbiguousTemplateException',
);

our $VERSION = "0.0_1";

require Exporter;
use AutoLoader qw(AUTOLOAD);
our @ISA; 
push @ISA, 'Exporter';

# If you do not need this, 
#   moving things directly into @EXPORT or @EXPORT_OK will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw( ) ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw{
    open_template
    template_named 
    add_template_file
    add_template_dir
    add_subs
    subs_library
};

my @searched_for_templates;
my %template_path;

my @searched_for_subs;
my %subs_path;
my $subs_library = App::Qtemp::SubsTable->new();

### INTERFACE SUB
# Subroutine: template_named
# Usage: template_named( $tname )
# Purpose: 
#   Search the template library for a template named $tname.
#   For example template_named( 'perl-lib' ).
# Returns: A string if the template is found. Undef otherwise.
# Throws: 
#   UnknownTemplateException when no template is found.
#   AmbiguousTemplateException when multiple templates are found.
sub template_named {
    my $tname = shift;
    my @matching_templates
        = grep {
            basename($_) =~ /\A $tname\.qtemp\z /xms;
        } keys %template_path;
    my $num_matching = scalar @matching_templates;
    if ($num_matching == 0) { UnknownTemplateException->throw(
        error => "No template with name $tname" ); }
    elsif ($num_matching == 1) { return $matching_templates[0]; }
    else { AmbiguousTemplateException->throw(
        error => join( "\n    ", 
            "Multiple matches for $tname:", 
            @matching_templates ) . "\n"); } 
}

# Subroutine: open_template($tname)
# Type: INTERNAL UTILITY
# Purpose: 
#   Read template named $tname.
# Returns: 
#   An App::Qtemp::Template object.
#   An undefined value if no template by that name is found.
sub open_template {
    my ($tmpl_name) = @_;
    return read_template_file( template_named( $tmpl_name ) );
}

### INTERFACE SUB
# Subroutine: add_template_file
# Usage: add_template_file( $path )
# Purpose: 
#   Add a single file not in a normal search path to the template library.
# Returns: Nothing
# Throws: Nothing
sub add_template_file {
    my $tpath = shift;
    return 0 if defined $template_path{$tpath};
    return $template_path{$tpath} = 1;
}

### INTERFACE SUB
# Subroutine: add_template_dir
# Usage: add_template_dir( $root_dir )
# Purpose: 
#   Search the directory hierarchy rooted at $root_dir for templates.
# Returns: The number of templates added to the directory.
# Throws: Nothing
sub add_template_dir {
    my $root_dir = shift;
    return if grep {$_ eq $root_dir} @searched_for_templates;
    my @files = find_hierarchy( $root_dir );
    my @templates = grep {$_ =~ /\.qtemp\z/xms} @files;
    my $num_added = 0;
    for my $t (@templates) { $num_added += add_template_file($t); }
    push @searched_for_templates, $root_dir;
    return $num_added;
}

### INTERNAL UTILITY
# Subroutine: _add_subs_file_
# Usage: _add_subs_file_( $subs_path )
# Purpose: Add the subs of a single file to the subs library.
# Returns: The number of subs added to the library.
# Throws: Nothing
sub _add_subs_file_ {
    my $sp = shift;
    my $subs_ref = parse_subs_file($sp);
    my $num_added = 0;
    for my $s (@{$subs_ref}) { 
        $subs_library->_add_($s->{key}, $s->{contents}); 
        ++$num_added;
    }
    return $num_added;
}

### INTERFACE SUB
# Subroutine: add_subs
# Usage: 
#   add_subs($pattern, $subs_string)
#   add_subs( $root_dir )
# Purpose: 
#   Add a substitution to the library if two arguments are given;
#   otherwise, search the directory hierarchy rooted at $root_dir for substitution files.
# Returns: The number of substitution files added to the library.
# Throws: Nothing
sub add_subs {
    my ($p,$s) = @_;
    if (defined $s) {
        $subs_library->add($p,$s);
        return 1;
    }
    my $root_dir = $p;
    return if grep {$_ eq $root_dir} @searched_for_subs;
    my @files = find_hierarchy( $root_dir );
    my @subs_files = grep {$_ =~ /\.subs\z/xms} @files;
    my $num_added = 0;
    for my $s (@subs_files) { 
        if (!defined $subs_path{ $s }) {
            _add_subs_file_($s);
            ++$num_added;
            $subs_path{$s} = 1;
        }
    }
    push @searched_for_subs, $root_dir;
    return $num_added;
}

### INTERFACE SUB
# Subroutine: subs_library
# Usage: subs_library( )
# Purpose: 
#   Retrieve an uncompiled copy of the current subtable library.
# Returns: App::Qtemp::SubsTable object.
# Throws: Nothing
sub subs_library {
    return $subs_library->dup();
}

return 1;

__END__

=head1 NAME

Library.pm - short description

=head1 VERSION

Version 0.0_1
Originally created on 11/11/10 22:42:23

=head1 DESCRIPTION

=head1 AUTHOR

Bryan Matsuo [bryan.matsuo@gmail.com]

=head1 BUGS

=over

=back

=head1 COPYRIGHT & LICENCE

(c) Bryan Matsuo [bryan.matsuo@gmail.com]
