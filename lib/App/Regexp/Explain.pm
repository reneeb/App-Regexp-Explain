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
    my $explanation = _explain( $tokenized->{tokens} );

    use Data::Printer;
    p $tokenized;
}

sub _explain {
    my ($tokens) = @_;

    my @explanations;

    my $cnt = 0;
    while ( @{ $tokens } ) {
        my $token = $tokens->[0];

        if ( $token->{type} eq Regexp::Lexer::TokenType::Character ) {
            push @explanations, +{ value => _find_longest_string( $tokens ), expl => 'Literal %s' } ;
        }
        elsif ( $token->{type} eq Regexp::Lexer::TokenType::LeftParenthesis ) {
            my $grouping = _grouping( $tokens );

            push @explanations, +{ value => $grouping->{value}, expl => $grouping->{expl} };
            push @explanations, @{ $grouping->{subexpressions} || [] };
        }
        elsif ( $token->{type} eq Regexp::Lexer::TokenType::RightParenthesis ) {
            push @explanations, +{ value => ')', expl => 'End of grouping' };
            shift @{ $tokens };
        }
        else {
            shift @{ $tokens }
        }

        last if ++$cnt > 10;
    }

    use Data::Printer;
    p @explanations;
print STDERR "test";
}

sub _grouping {
    my ($tokens) = @_;

    my $grouping_string = '(';
    my $grouping_type;
    my $explanation;
    my $last;

    my $shifts;

    shift @{ $tokens };
    if ( $tokens->[0]->{char} eq '?' ) {
        if ( $tokens->[1]->{char} eq '!' ) {
            $explanation = 'negative lookahead';
            $shifts      = 2;
        }
        elsif ( $tokens->[1]->{char} eq '=' ) {
            $explanation = 'positive lookahead';
            $shifts      = 2;
        }
        elsif ( $tokens->[1]->{char} eq '<' ) {
            if ( $tokens->[2]->{char} eq '!' ) {
                $explanation = 'negative lookbehind';
                $shifts      = 3;
            }
            elsif ( $tokens->[2]->{char} eq '=' ) {
                $explanation = 'positive lookbehind';
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

        while ( @{ $tokens } ) {
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

        my $token = shift @{ $tokens };
        $string .= $token->{char};
    }

    return $string;
}

1;
