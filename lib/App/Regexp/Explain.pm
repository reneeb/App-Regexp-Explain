package App::Regexp::Explain;

# ABSTRACT: Explain regular expressions

use strict;
use warnings;

use Regexp::Lexer qw(tokenize);
use Regexp::Lexer::TokenType;
use Carp;
use Exporter;

our @EXPORT_OK = qw(
    re_explain
);

our $VERSION = 0.01;

sub re_explain {
    my ($re) = @_;

    croak 'no regex given' if !defined $re;

    if ( !ref $re ) {
        $re = qr/$re/;
    }

    my $tokenized   = tokenize( $re );

    use Data::Printer;
    #p $tokenized;

    my $explanation = _explain( $tokenized->{tokens} );
}

sub _explain {
    my ($tokens) = @_;

    my @explanations;

    my $cnt         = 0;
    my $level       = 0;
    my $group_count = 0;

    while ( @{ $tokens } ) {
        my $token = $tokens->[0];

        last if !$token->{type};

        if ( $token->{type} eq Regexp::Lexer::TokenType::Character and $tokens->[1] and _is_quantifier( $tokens->[1]->{type} ) ) {
            my $flexible = _find_flexible( $tokens );
            push @explanations, +{
                value => $flexible->{value},
                expl  => $flexible->{expl},
                level => $level,
            } ;
        }
        elsif ( $token->{type} eq Regexp::Lexer::TokenType::Character ) {
            push @explanations, +{
                value => _find_longest_string( $tokens ),
                expl  => 'Literal %s',
                level => $level,
            } ;
        }
        elsif ( $token->{type} eq Regexp::Lexer::TokenType::LeftParenthesis ) {
            my $grouping = _grouping( $tokens, \$group_count );
            $level++;

            push @explanations, +{
                value => $grouping->{value},
                expl  => $grouping->{expl},
                level => $level,
            };
        }
        elsif ( $token->{type} eq Regexp::Lexer::TokenType::RightParenthesis ) {
            push @explanations, +{
                value => ')',
                expl  => 'End of grouping',
                level => $level,
            };
            $level--;
            shift @{ $tokens };

            if ( _is_quantifier( $tokens->[0]->{type} ) ) {
                my $quantifier_string = _quantifier_string( $tokens );

                $explanations[-1]->{expl} .= ' ' . $quantifier_string;
            }
        }
        elsif ( $token->{type} eq Regexp::Lexer::TokenType::Alternation ) {
            push @explanations, +{
                value => '|',
                expl  => 'Alternation (or)',
                level => $level,
            };
            $level--;
            shift @{ $tokens };
        }
        else {
            shift @{ $tokens }
        }

        last if ++$cnt > 100;
    }

    use Data::Printer;
    p @explanations;
print STDERR "test";
}

sub _grouping {
    my ($tokens, $nr) = @_;

    my $grouping_string = '(';
    my $grouping_type;
    my $explanation = 'Capturing group $%s';
    my $last;
    my $non_capture;

    my $shifts;

    shift @{ $tokens };
    if ( $tokens->[0]->{char} eq '?' ) {
        $non_capture++;

        if ( $tokens->[1]->{char} eq '!' ) {
            $explanation = 'negative lookahead';
            $grouping_string .= '?!';
            $shifts      = 2;
        }
        elsif ( $tokens->[1]->{char} eq '=' ) {
            $explanation = 'positive lookahead';
            $grouping_string .= '?=';
            $shifts      = 2;
        }
        elsif ( $tokens->[1]->{char} eq '<' ) {
            if ( $tokens->[2]->{char} eq '!' ) {
                $explanation = 'negative lookbehind';
                $grouping_string .= '?<!';
                $shifts      = 3;
            }
            elsif ( $tokens->[2]->{char} eq '=' ) {
                $explanation = 'positive lookbehind';
                $grouping_string .= '?<=';
                $shifts      = 3;
            }
        }

        $last = 1 if $shifts;
    }

    if ( $last ) {
        splice @{ $tokens }, 0, $shifts;
    }
    else {
        my %modifiers;
        my $key = 'plus';

        if ( $tokens->[1]->{char} eq '<' ) {
           my %named_capture = _named_capture( $tokens );
           $grouping_string .= $named_capture{value};
           $explanation     .= ' captured to $-{' . $named_capture{name} . '}';
           $non_capture = 0;
        }

        while ( @{ $tokens } ) {
            last if !$non_capture;
            last if $tokens->[0]->{type} eq Regexp::Lexer::TokenType::LeftParenthesis;
            last if $tokens->[0]->{type} eq Regexp::Lexer::TokenType::RightParenthesis;

            my $token = shift @{ $tokens };

            $grouping_string .= $token->{char};

            if ( $token->{char} eq '-' ) {
                $key = 'minus';
            }
            elsif ( $token->{char} eq ':' ) {
                $explanation = 'non-capturing group ' . $explanation;
            }

            last if $token->{type} eq Regexp::Lexer::TokenType::Colon;

            push @{ $modifiers{$key} }, $token->{char} if $token->{char} =~ m/[a-z]/;
        }

        if ( $modifiers{plus} ) {
            $explanation .= ' activated modifiers: ';
            $explanation .= join ', ', @{ $modifiers{plus} || [] };
        }

        if ( $modifiers{minus} ) {
            $explanation .= ' deactivated modifiers: ';
            $explanation .= join ', ', @{ $modifiers{plus} || [] };
        }
    }

    if ( !$non_capture ) {
        $explanation = sprintf $explanation, ++${$nr};
    }

    my %grouping = (
        value => $grouping_string,
        expl  => $explanation,
    );

    return \%grouping;
}

sub _find_longest_string {
    my ($tokens) = @_;

    my $string = '';
    while ( @{ $tokens } ) {
        last if $tokens->[0]->{type} ne Regexp::Lexer::TokenType::Character;
        if (
            $tokens->[1] && 
            $tokens->[1]->{type} ne Regexp::Lexer::TokenType::Character &&
            _is_quantifier( $tokens->[1]->{type} ) ) {
        }

        my $token = shift @{ $tokens };
        $string .= $token->{char};
    }

    return $string;
}

sub _find_flexible {
    my ($tokens) = @_;

    my $char_token = shift @{ $tokens };
    my %quantifier = _quantifier( $tokens );

    my %flexible = (
        value => $char_token->{char} . $quantifier{value},
        expl  => $char_token->{char} . $quantifier{expl},
    );

    return \%flexible;
}

sub _quantifier {
    my ($tokens) = @_;

    my %quantifier = ( value => '', expl => '' );
    my $last_quantifier = '';
    my $between_braces;
    my $key = 'min';
    my %borders;

warn $tokens->[0]->{char};

    while ( @{ $tokens } ) {
        last if !_is_quantifier( $tokens->[0]->{type} ) && !$between_braces;

        my $token = shift @{ $tokens };
        my $char  = $token->{char};

        $quantifier{value} .= $char;

        if ( $char eq '?' && !$last_quantifier ) {
            $quantifier{expl} .= ' 0 or 1 time';
        }
        elsif ( $char eq '?' && $last_quantifier ) {
            $quantifier{expl} .= ' (non-greedy)';
        }
        elsif ( $char eq '+' && !$last_quantifier ) {
            $quantifier{expl} .= ' 1 or many times';
        }
        elsif ( $char eq '+' && $last_quantifier ) {
            $quantifier{expl} .= ' (without backtracking)';
        }
        elsif ( $char eq '*' && !$last_quantifier ) {
            $quantifier{expl} .= ' 0, 1 or many times';
        }
        elsif ( $char eq '*' && $last_quantifier ) {
            $quantifier{expl} .= ' (greedy)';
        }
        elsif ( $char eq ',' && $between_braces ) {
            $key = 'max';
        }
        elsif ( $char =~ /\A[0-9]\z/ && $between_braces ) {
            $borders{$key} .= $char;
        }
        elsif ( $char eq '{' ) {
            $between_braces++;
        }
        elsif ( $char eq '}' ) {
            $between_braces = 0;
            if ( $borders{min} && $borders{max} ) {
                $quantifier{expl} .= sprintf ' between %s and %s times', $borders{min}, $borders{max};
            }
            elsif ( $borders{min} ) {
                $quantifier{expl} .= sprintf 'at least %s times', $borders{min};
            }
            elsif ( $borders{max} ) {
                $quantifier{expl} .= sprintf 'at most %s times', $borders{max};
            }
        }

        $last_quantifier = $char;
    }

    return %quantifier;
}

sub _named_capture {
    my ($tokens) = @_;

    my %named_capture = ( value => '', name => '' );

    while ( @{ $tokens } ) {
        my $token = shift @{ $tokens };
        my $char  = $token->{char};

        $named_capture{value} .= $char;
        $named_capture{name}  .= $char if $token->{type} eq Regexp::Lexer::TokenType::Character;

        last if $token->{type} eq Regexp::Lexer::TokenType::RightAngle;
    }

    return %named_capture;
}

sub _is_quantifier {
    my ($type) = @_;

    return if !$type;

    return 1 if $type eq Regexp::Lexer::TokenType::Plus;
    return 1 if $type eq Regexp::Lexer::TokenType::Asterisk;
    return 1 if $type eq Regexp::Lexer::TokenType::LeftBrace;
    return 1 if $type eq Regexp::Lexer::TokenType::Question;
    return;
}

1;
