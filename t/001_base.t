#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use File::Basename;
use File::Spec;
use File::Glob qw(bsd_glob);

use App::Regexp::Explain qw(re_explain);

my $dir = File::Spec->catdir( dirname( __FILE__ ), '001' );
my @files = bsd_glob( "$dir/*.regex" );

for my $file ( @files ) {
    my $content      = do{ local (@ARGV, $/) = $file; <> };
    my ($re, $check) = split /=====/, $content;
    $re =~ s/\x0a//g;

    App::Regexp::Explain::re_explain( $re );
}

done_testing();
