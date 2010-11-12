#!/usr/bin/env perl

# Use perldoc or option --man to read documentation
package App::Qtemp::Library;

use strict;
use warnings;
use Carp;
use File::Basename;
use App::Qtemp::DirUtils;
use App::Qtemp::Template;

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
    add_to_library};

my @searched;
my %template_path;

### INTERFACE SUB
# Subroutine: template_named
# Usage: template_named( $tname )
# Purpose: 
#   Search the template library for a template named $tname.
#   For example template_named( 'perl-lib' ).
# Returns: A string if the template is found. Undef otherwise.
# Throws: Nothing
sub template_named {
    my $tname = shift;
    my @matching_templates
        = grep {
            basename($_) =~ /\A $tname\.qtemp\z /xms;
        } keys %template_path;
    my $num_matching = scalar @matching_templates;
    if ($num_matching == 0) { return; }
    elsif ($num_matching == 1) { return $matching_templates[0]; }
    else { return; } # TODO: Throw an exception.
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

    my $template_path = template_named($tmpl_name);

    # Ensure that the template was found.
    croak(
        sprintf "%s\n", 
            join("\n\t","Couldn't find template $tmpl_name in", @searched)
    ) if !defined $template_path;

    # Read and return the template.
    my $template = read_template_file($template_path);
    return $template;
}

### INTERFACE SUB
# Subroutine: add_to_library
# Usage: add_to_library( $root_dir )
# Purpose: 
#   Search the directory hierarchy rooted at $root_dir for templates.
# Returns: The number of templates added to the directory.
# Throws: Nothing
sub add_to_library {
    my $root_dir = shift;
    return if grep {$_ eq $root_dir} @searched;
    my @files = find_hierarchy( $root_dir );
    my @templates = grep {$_ =~ /\.qtemp\z/xms} @files;
    my $num_added = 0;
    for my $t (@templates) { 
        ++$num_added if !defined $template_path{ $t };
        $template_path{$t} = 1 ;
    }
    push @searched, $root_dir;
    return $num_added;
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
