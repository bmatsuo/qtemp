#!/usr/bin/env perl

package App::Qtemp::DirUtils;

use strict;
use warnings;
use Carp;
use File::Glob qw{bsd_glob};
require Exporter;
use AutoLoader qw(AUTOLOAD);
our @ISA;
push @ISA, 'Exporter';

our @EXPORT = qw{
    glob_safe 
    find_pattern
    subdirs_of
    find_hierarchy
};

# Turn a path into one acceptable by bsd_glob, with no unintended meaning.
sub glob_safe {
    my $str = shift;
    # Let bsd_glob expand ~ to the home directory.
    $str =~ s/( \[ | \] | \\ | [{}*?] )/\\$1/gxms;
    return $str;
}

# Find files directly contained in a directory that match a given pattern.
sub find_pattern {
    my ($dir, $patt) = @_;
    my $glob_str = join '/', glob_safe($dir), $patt;
    return bsd_glob($glob_str);
}

# Find subdirectories of a given directory.
# Return a list of full paths to subdirectories.
sub subdirs_of {
    my $dir = shift;
    return grep { -d $_ } find_pattern($dir, '*');
}

# Find all files (directly or indirectly) contained in a given directory.
sub find_hierarchy{
    my $dir = shift;
    return ($dir) if !-d bsd_glob(glob_safe($dir));
    return ($dir, (map {(find_hierarchy($_))} find_pattern($dir, '*')));
}

1;

__END__
