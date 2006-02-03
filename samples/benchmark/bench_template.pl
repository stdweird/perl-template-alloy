#!/usr/bin/perl -w

=head1 NAME

bench_template.pl - Test relative performance of CGI::Ex::Template to Template::Toolkit

=cut

use strict;
use Benchmark qw(cmpthese timethese);
use POSIX qw(tmpnam);
use File::Path qw(rmtree);
use CGI::Ex::Template;
use CGI::Ex::Dump qw(debug);
use Template;

my $tt_cache_dir = tmpnam;
END { rmtree $tt_cache_dir };
mkdir $tt_cache_dir, 0755;

my @config1 = (ABSOLUTE => 1, CONSTANTS => {fefifo => sub {'do_once'}, simple => 'var'}, EVAL_PERL => 1);
#push @config1, (INTERPOLATE => 1);
my @config2 = (@config1, COMPILE_EXT => '.ttc');

my $tt1 = Template->new(@config1);
my $tt2 = Template->new(@config2);

my $cet = CGI::Ex::Template->new(@config1);
my $cetc = CGI::Ex::Template->new(@config2);

my $swap = {
    one   => "ONE",
    two   => "TWO",
    three => "THREE",
    a_var => "a",
    hash  => {a => 1, b => 2, c => { d => [{hee => ["hmm"]}] }},
    array => [qw(A B C D E a A)],
    code  => sub {"($_[0])"},
    cet   => $cet,
    filt  => sub {sub {$_[0]x2}},
};
#$swap->{$_} = $_ for (1 .. 1000); # swap size affects benchmark speed

### set a few globals that will be available in our subs
my $show_list = grep {$_ eq '--list'} @ARGV;
my $run_all   = grep {$_ eq '--all'}  @ARGV;
my @run = $run_all ? () : @ARGV;
my $str_ref;
my $filename;



###----------------------------------------------------------------###

### uncomment to run a specific test - otherwise all tests run
#@run = qw(_07_var_sma);

#                                                                         ### All percents are CGI::Ex::Template vs TT2
#                                                                         ### (The percent that CET is faster than TT)
#                                                                     New object with CACHE_DIR set #
#                                      This percent is compiled in memory (repeated calls) #        #
#                                         New object each time (undef CACHE_SIZE) #        #        #
my $tests = {                                                            #        #        #        #
    _01_empty     => "",                                                 #  540%  # 1067%  #  608%  #
    _02_mixed_sma => "".((" "x1000)."[% one %]\n")x10,                   #   79%  #  637%  #  265%  #
    _03_mixed_med => "".((" "x1000)."[% one %]\n")x100,                  #   40%  #  560%  #  127%  #
    _04_mixed_lar => "".((" "x10)."[% one %]\n")x1000,                   #   -6%  #  415%  #   24%  #
    _05_str_sma   => "".("[% \"".(" "x1000)."\$one\" %]\n")x10,          #  -32%  # 313270%#  102%  #
    _06_str_lar   => "".("[% \"".(" "x10)."\$one\" %]\n")x1000,          #  -59%  #  335%  #  -30%  #
    _07_var_sma   => "[% one %]",                                        #  320%  #  902%  #  583%  #
    _08_var_med   => "[% one %]"x20,                                     #   48%  #  470%  #  161%  #
    _09_var_lar   => "[% one %]"x200,                                    #    8%  #  381%  #   36%  #
    _10_plus      => "([% 1 + 2 %])",                                    #  134%  #  635%  #  382%  #
    _11_plus_lar  => "[% 1 + 2 + 3 + 5 + 6 + 8 %]",                      #  110%  #  426%  #  384%  #
    _12_set       => "[% SET one = 2 %]",                                #  296%  #  778%  #  528%  #
    _13_set_range => "[% SET one = [0..30] %]",                          #   63%  #  441%  #  304%  #
    _14_chained   => "[% c.d.0.hee.0 %]",                                #  356%  #  973%  #  572%  #
    _15_chain_lar => "".((" "x10)."[% c.d.0.hee.0 %]\n")x1000,           #   66%  #  626%  #   61%  #
    _16_cplx_comp => "[% t = 1 || 0 ? 0 : 1 || 2 ? 2 : 3 %][% t %]",     #  108%  #  381%  #  316%  #
    _17_if_simple => "[% a=1 %][% IF a %]Two[% END %]",                  #  193%  #  650%  #  419%  #
    _18_for_i_sml => "[% FOREACH i = [0..10] %][% i %][% END %]",        #   18%  #  263%  #  160%  #
    _19_for_i_med => "[%i=1 ; FOREACH i = [0..100] ; i ; END ; i%]",     #  -17%  #   46%  #   12%  #
    _20_for_i_lar => "[%i=1 ; FOREACH i = [0..1000] ; i ; END ; i%]",    #  -19%  #  -12%  #  -17%  #
    _21_for_sml   => "[%i=1 ; FOREACH [0..10] ; i ; END ; i %]",         #   34%  #  305%  #  181%  #
    _22_for_med   => "[%i=1 ; FOREACH [0..100] ; i ; END ; i %]",        #    7%  #   82%  #   42%  #
    _23_for_lar   => "[%i=1 ; FOREACH [0..1000] ; i ; END ; i %]",       #    0%  #   12%  #    6%  #
    _24_while     => "[%f=10%][%WHILE f%][%f=f- 1%][%f%][% END %]",      #  -17%  #  153%  #   48%  #
    _25_whl_set_l => "[%f=10; WHILE (g=f) ; f = f - 1 ; f ; END %]",     #   -9%  #  148%  #   53%  #
    _26_whl_set_m => "[%f=5; WHILE (g=f) ; f = f - 1 ; f ; END %]",      #    6%  #  244%  #  102%  #
    _27_whl_set_s => "[%f=1; WHILE (g=f) ; f = f - 1 ; f ; END %]",      #   74%  #  422%  #  252%  #
    _28_process   => "[% BLOCK foo %]Hi[% END %][% PROCESS foo %]",      #  358%  #  843%  #  572%  #
    _29_include   => "[% BLOCK foo %]Hi[% END %][% INCLUDE foo %]",      #  314%  #  798%  #  545%  #
    _30_macro     => "[% MACRO foo BLOCK %]Hi[% END %][% foo %]",        #  135%  #  512%  #  356%  #
    _31_macro_arg => "[% MACRO foo(n) BLOCK %]Hi[%n%][%END%][%foo(2)%]", #  102%  #  345%  #  308%  #
    _32_macro_pro => "[% MACRO foo PROCESS bar;BLOCK bar%]7[%END;foo%]", #  174%  #  449%  #  415%  #
    _33_filter    => "[% n = 1 %][% n FILTER repeat(2) %]",              #  114%  #  453%  #  343%  #
    _34_fltr_name => "[% n=1; n FILTER echo=repeat(2); n FILTER echo%]", #   40%  #  375%  #  243%  #
    _35_constant  => "[% constants.fefifo %]",                           #  355%  #  875%  #  633%  #
    _36_constant2 => "[% constants.simple %]",                           #  346%  #  931%  #  628%  #
#    _37_interp    => "Foo \$one Bar" => 'Foo ONE Bar'; # set INTERPOLATE #  287%  #  849%  #  536%  #
    _38_perl      => "[%one='ONE'%][% PERL %]print \"[%one%]\"[%END%]",  #   98%  #  528%  #  304%  #
    _39_filtervar => "[% 'hi' | \$filt %]",                              #  167%  #  738%  #  514%  #
    _40_filteruri => "[% ' ' | uri %]",                                  #  137%  #  742%  #  484%  #
};

if ($show_list) {
    seek DATA, 0, 0;
    local $/ = undef;
    my $data = <DATA>;
    foreach my $key (sort keys %$tests) {
        $data =~ m/([^\S\n]+\Q$key\E.*)/ || next;
        print "$1\n";
    }
    exit;
}

###----------------------------------------------------------------###

sub file_TT_new {
    my $out = '';
    my $t = Template->new(@config1);
    $t->process($filename, $swap, \$out);
    return $out;
}

sub str_TT_new {
    my $out = '';
    my $t = Template->new(@config1);
    $t->process($str_ref, $swap, \$out);
    return $out;
}

sub file_TT {
    my $out = '';
    $tt1->process($filename, $swap, \$out);
    return $out;
}

sub str_TT {
    my $out = '';
    $tt1->process($str_ref, $swap, \$out) || debug $tt1->error;
    return $out;
}

sub file_TT_cache_new {
    my $out = '';
    my $t = Template->new(@config2);
    $t->process($filename, $swap, \$out);
    return $out;
}

###----------------------------------------------------------------###

sub file_CET_new {
    my $out = '';
    my $t = CGI::Ex::Template->new(@config1);
    $t->process($filename, $swap, \$out);
    return $out;
}

sub str_CET_new {
    my $out = '';
    my $t = CGI::Ex::Template->new(@config1);
    $t->process($str_ref, $swap, \$out);
    return $out;
}

sub file_CET {
    my $out = '';
    $cet->process($filename, $swap, \$out);
    return $out;
}

sub str_CET {
    my $out = '';
    $cet->process($str_ref, $swap, \$out);
    return $out;
}

sub str_CET_swap {
    my $txt = $cet->swap($str_ref, $swap);
    return $txt;
}

sub file_CET_cache_new {
    my $out = '';
    my $t = CGI::Ex::Template->new(@config2);
    $t->process($filename, $swap, \$out);
    return $out;
}

###----------------------------------------------------------------###

@run = sort(keys %$tests) if $#run == -1;

my $output = '';
my %cumulative;
foreach my $test_name (@run) {
    die "Invalid test $test_name" if ! exists $tests->{$test_name};
    my $txt = $tests->{$test_name};
    my $sample = (length($txt) > 40) ? substr($txt,0,40).'...' : $txt;
    print "-------------------------------------------------------------\n";
    print "Running test $test_name\n";
    print "Test text: \"$sample\"\n";

    ### set the global file types
    $str_ref = \$txt;
    $filename = $tt_cache_dir ."/$test_name.tt";
    open(my $fh, ">$filename") || die "Couldn't open $filename: $!";
    print $fh $txt;
    close $fh;

    #debug file_CET(), str_TT();
    #debug $cet->parse_tree($file);

    ### check out put - and also allow for caching
    for (1..2) {
        if (file_CET() ne str_TT()) {
            debug $cet->parse_tree($str_ref);
            debug file_CET(), str_TT();
            die "file_CET didn't match";
        }
        die "file_TT didn't match "            if file_TT()      ne str_TT();
        die "str_CET didn't match "            if str_CET()      ne str_TT();
#        die "str_CET_swap didn't match "       if str_CET_swap() ne str_TT();
        die "file_CET_cache_new didn't match " if file_CET_cache_new() ne str_TT();
        die "file_TT_cache_new didn't match " if file_TT_cache_new() ne str_TT();
    }

###----------------------------------------------------------------###

    my $r = eval { timethese (-2, {
        file_TT_n   => \&file_TT_new,
#        str_TT_n    => \&str_TT_new,
        file_TT     => \&file_TT,
        str_TT      => \&str_TT,
        file_TT_c_n => \&file_TT_cache_new,

        file_CT_n   => \&file_CET_new,
#        str_CT_n    => \&str_CET_new,
        file_CT     => \&file_CET,
        str_CT      => \&str_CET,
#        str_CT_sw   => \&str_CET_swap,
        file_CT_c_n => \&file_CET_cache_new,
    }) };
    if (! $r) {
        debug "$@";
        next;
    }
    eval { cmpthese $r };

    $output .= sprintf('%-20s', $test_name);

    eval {
        my $hash = {
            '1 cached_in_memory           ' => '',
            '2 new_object                 ' => '_n',
            '3 cached_on_file (new_object)' => '_c_n',
            '4 string reference           ' => 'str',
        };
        foreach my $type (sort keys %$hash) {
            my $suffix = $hash->{$type};
            my $prefix = 'file';
            ($prefix, $suffix) = ('str', '') if $suffix eq 'str';
            my $ct = $r->{"${prefix}_CT$suffix"};
            my $tt = $r->{"${prefix}_TT$suffix"};
            my $ct_s = $ct->iters / ($ct->cpu_a || 1);
            my $tt_s = $tt->iters / ($tt->cpu_a || 1);
            my $p = int(100 * ($ct_s - $tt_s) / ($tt_s || 1));
            print "$type - CT is $p% faster than TT\n";

            $output .= sprintf('#  %3s%%  ', $p);

            ### store cumulatives
            if (abs($p) < 10000) {
                $cumulative{$type} ||= [0, 0];
                $cumulative{$type}->[0] += $p;
                $cumulative{$type}->[1] ++;
            }
        }
    };
    debug "$@"
        if $@;

    $output .= "#\n";

    foreach my $row (values %cumulative) {
        $row->[2] = sprintf('%.1f', $row->[0] / ($row->[1]||1));
    }

    debug \%cumulative
        if $#run > 0;
}

print $output;

#print `ls -lR $tt_cache_dir`;
__DATA__
