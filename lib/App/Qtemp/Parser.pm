#!/usr/bin/env perl

package TObj;
sub dependent_subs { return () }
sub dependent_templates { return () }
package TSub;
push @ISA, 'TObj';
sub dependent_subs {
    my $self = shift;
    return ($self->{key});
}
sub dependent_templates {
    my $self = shift;
    return ();
}
package TSubDefn;
push @ISA, 'TObj';
sub dependent_subs {
    my $self = shift;
    return (map {$_->dependent_subs} @{$self->{contents}});
}
sub dependent_templates {
    my $self = shift;
    return (map {$_->dependent_templates} @{$self->{contents}});
}
package TPipe;
push @ISA, 'TObj';
sub dependent_subs {
    my $self = shift;
    return (map {$_->dependent_subs} @{$self->{contents}});
}
sub dependent_templates {
    my $self = shift;
    return (map {$_->dependent_templates} @{$self->{contents}});
}
package TIncl;
push @ISA, 'TObj';
sub dependent_subs {
    my $self = shift;
    return (map {(map {$_->dependent_subs} $_->contents)} @{$self->{sub_defs}});
}
sub dependent_templates {
    my $self = shift;
    return (
        $self->{name} ,
        (   map {
                (map {$_->dependent_templates} @{$_->contents})
            } @{$self->{sub_defs}}),
    );
}
package TCondSub;
push @ISA, 'TObj';
sub dependent_subs {
    my $self = shift;
    return (
        (map {$_->dependent_subs} @{$self->{true_contents}}),
        (map {$_->dependent_subs} @{$self->{false_contents}})
    );
}
sub dependent_templates {
    my $self = shift;
    return (
        (map {$_->dependent_templates} @{$self->{true_contents}}),
        (map {$_->dependent_templates} @{$self->{false_contents}})
    );
}
package TStr;
push @ISA, 'TObj';
sub dependent_subs { return () }
sub dependent_templates { return () }
package TRoot;
push @ISA, 'TObj';
sub dependent_subs {
    my $self = shift;
    return (
        (map {$_->dependent_subs} @{$self->{script}}),
        (map {$_->dependent_subs} @{$self->{contents}}),
        (map {(map {$_->dependent_subs} $_->{contents})} @{$self->{sub_defs}}),
    );
}
sub dependent_templates {
    my $self = shift;
    return (
        (map {$_->dependent_templates} @{$self->{script}}),
        (map {$_->dependent_templates} @{$self->{contents}}),
        (   map {
                (map {$_->dependent_templates} $_->{contents})
            } @{$self->{sub_defs}}),
    );
}
package App::Qtemp::Parser;
use strict;
use warnings;
use Parse::RecDescent;
use Data::Dumper;
require Exporter;
use AutoLoader qw(AUTOLOAD);
our @ISA; 
push @ISA, 'Exporter';

# If you do not need this, 
#   moving things directly into @EXPORT or @EXPORT_OK will save memory.
our %EXPORT_TAGS = ( all => [ qw( ) ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{all} } );
our @EXPORT = qw{parse_template parse_subs parse_sub_contents};


$Parse::RecDescent::skip='';

local $::RD_HINT = 1;
#local $::RD_TRACE = 1;
my $debugging = 1;
sub dbg {
    return $debugging;
}

my $template;
sub found_template {
    my $t = shift;
    $template = $t;
}

my $subs_ref;
sub found_subs {
    my $s = shift;
    $subs_ref = $s
}

my $sub_contents_ref;
sub found_sub_contents {
    my $c = shift;
    $sub_contents_ref = $c;
}

my $token_set = <<'EOTOKENS';
    SIGIL:      /\$/
    WS:         /\s+/
    NL:         /\n/
    TNAME:      /\w(?:\w|[-])*/
    SUBKEY:     /\w+/
    EQ:         /=/
    BANG:       /!/
    QUEST:      /\?/
    DQUOTE:     /"/
    NODQUOTE:   /[^"]|\\\\"/
    LPAREN:     /\(/
    RPAREN:     /\)/
    LBRACK:     /\[/
    RBRACK:     /\]/
    LBRACE:     /\{/
    RBRACE:     /\}/
    NORP:       /(?:[^)]|\\\\[)])/
    NORBRACE:   /[^}]|\\\\[}]/
    WILD:       /[^\$]/

EOTOKENS

my $templ_rules = <<'EOTGRAMMAR';
    SubPattern: 
        LBRACE SUBKEY RBRACE { $item[2] }
        | SUBKEY
        | SIGIL

    Substitution: SIGIL SubPattern { bless {key => $item[2]}, 'TSub' }

    PipeComponent:
        SystemPipe
        | ConditionalSubstitution
        | Substitution
        | Include
        | NORP { bless {val => $item[1]}, 'TStr' }

    PipeContents: PipeComponent(s)

    SystemPipe:
        SIGIL LPAREN PipeContents RPAREN 
            { bless {contents => $item[3]}, 'TPipe' }

    SubPatternComponent:
        SystemPipe
        | ConditionalSubstitution
        | Substitution
        | Include
        | NODQUOTE { bless {val => $item[1]}, 'TStr' }

    SubPatternContents: SubPatternComponent(s)

    OptionalWhitespace: WS | { [] }

    NoWSSubDefinition: 
        SUBKEY EQ DQUOTE SubPatternContents DQUOTE
            { bless {key => $item[1], contents => $item[4]}, 'TSubDefn' }

    SubDefinition:
        OptionalWhitespace NoWSSubDefinition { $item[2] }

    SubDefnList: SubDefinition(s) 

    IncludeBegin: SIGIL LBRACK

    IncludeRest: TNAME IncludeEnd { [@item[1,2]] }

    IncludeEnd: 
        WS SubDefnList RBRACK { $item[2] }
        | RBRACK { [] }

    Include:
        IncludeBegin IncludeRest 
            {   bless {
                    template => $item[2]->[0],
                    sub_defs => $item[2]->[1] }, 'TIncl' }

    ConditionComponent:
        SystemPipe
        | ConditionalSubstitution
        | Substitution
        | Include
        | NORBRACE { bless { val => $item[1] }, 'TStr' }

    Condition: ConditionComponent(s)

    Negation: BANG { 1 } | { 0 }

    CondSubBegin: SIGIL QUEST Negation SUBKEY QUEST 
        { {negated => $item[3], key => $item[4] } }

    CondCase: LBRACE Condition RBRACE { $item[2] }

    ElseCase: CondCase | { [] }

    CondCases:
        CondCase ElseCase { { true => $item[1], false => $item[2] } }

    ConditionalSubstitution:
        CondSubBegin CondCases 
            { bless {negated => $item[1]->{negated},
                key => $item[1]->{key},
                true_contents => $item[2]->{true},
                false_contents => $item[2]->{false}}, 'TCondSub' }

    SectionTerminator: NL BANG BANG NL { bless {}, 'TSTerm' }

    TemplateComponent:
        SystemPipe
        | ConditionalSubstitution
        | Substitution
        | Include
        | SectionTerminator
        | WILD { bless {val => $item[1]}, 'TStr' }

    SubDefnLine: NoWSSubDefinition NL { $item[1] }

    SubDefnLineList: SubDefnLine(s)

    SubsDefnSection: SubDefnLineList BANG BANG NL { $item[1] }

    InnerTemplate: TemplateComponent(s)

    Template:
        SubsDefnSection InnerTemplate
            { App::Qtemp::Parser::found_template( 
                bless {sub_defs=>$item[1], contents=>$item[2]}, 'TRoot' ) }
        | InnerTemplate 
            { App::Qtemp::Parser::found_template( bless {sub_defs=>[], contents=>$item[1]}, 'TRoot') }

    SubstitutionList: SubDefnLineList { App::Qtemp::Parser::found_subs( $item[1] ) }

    SubstitutionContents: SubPatternContents {App::Qtemp::Parser::found_sub_contents( $item[1] ) }
EOTGRAMMAR

my $templ_grammar = $token_set.$templ_rules;

my $tparser = Parse::RecDescent->new($templ_grammar);

sub compress_strings {
    my @components;
    my $want_to_compress = 0;
    for my $c (@{$_[0]}) {
        #print {\*STDERR} "Compressing ".ref ($c)."...\n";
        if ($c->isa('TStr')) {
            if ($want_to_compress) {
                my $last_c = $components[-1];
                $last_c->{val} = $last_c->{val}.$c->{val};
                next;
            }
            $want_to_compress = 1;
        }
        else {
            if ($c->isa('TSubDefn')) {
                compress_strings($c->{sub_contents});
            }
            elsif ($c->isa('TCondSub')) {
                compress_strings($c->{true_contents});
                compress_strings($c->{false_contents});
            }
            elsif ($c->isa('TPipe')) {
                compress_strings($c->{contents});
            }
            elsif ($c->isa('TIncl')) {
                compress_strings($c->{sub_defs});
            }
            elsif ($c->isa('TSub')) {
            }
            elsif ($c->isa('TSTerm')) {
            }
            else {
                die sprintf ("Unknown object type %s\n", ref $c);
            }
            $want_to_compress = 0;
        }
        push @components, $c;
    }

    if (@_) {
        splice @{$_[0]}, 0, scalar(@{$_[0]}), @components;
    }
}

sub extract_script {
    my $t = shift;
    my @contents = @{$t->{contents}};
    my @script;
    my $num_components = scalar @contents;
    for my $sep_i (0 ... $num_components - 1) {
        if (defined ($contents[$sep_i]) && $contents[$sep_i]->isa('TSTerm')) {
            @script = @contents[$sep_i ... $#contents];
            splice @{$t->{contents}}, $sep_i, scalar @script;
            shift @script;
        }
    }
    $t->{script} = [@script];
}

sub parse_template {
    my $text = shift;
    defined $tparser->Template($text) or die "Couldn't parse template.";
    for my $s (@{$template->{subdefs}}) {
        
    }
    compress_strings($template->{sub_defs});
    compress_strings($template->{contents});
    extract_script($template);
    return $template;
}

sub parse_subs {
    my $text = shift;
    defined $tparser->SubstitutionList($text) or die "Couldn't parse substitutions.";
    for my $s (@{$subs_ref}) {
        compress_strings($s->{contents});
    }
    return $subs_ref;
}

sub parse_sub_contents {
    my $text = shift;
    defined $tparser->SubstitutionContents($text) or die "Couldn't parse substitution contents.";
    compress_strings($sub_contents_ref);
    return $sub_contents_ref;
}

1;
__END__
