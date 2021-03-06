#!/usr/bin/perl -w

=head1 NAME

bench_tree_play.pl - Test various ways of Look at different ways of storing operators and how to call them

=cut

use strict;
use Benchmark qw(cmpthese timethese);
use CGI::Ex::Dump qw(debug);

#my $x = '.';
#my $y = 0;
#my $z = 0;
#my ($nx, $ny, $nz);
#cmpthese timethese -1, {
#    str_eq => sub { $nx++ if '.' eq $x },
#    num_eq => sub { $ny++ if 0 == $y },
#    undef  => sub { $nz++ if ! $z },
#};
##str_eq 6659358/s     --   -21%   -32%
##num_eq 8385413/s    26%     --   -14%
##undef  9799775/s    47%    17%     --

#my $tree1 = [([0, "foo\n"]) x 6];
#my $tree2 = [("foo\n") x 6];
#cmpthese timethese -2, {
#    data => sub { my $t = ''; foreach (@$tree1) { if (! $_->[0]) { $t.= $_->[1] } } },
#    bare => sub { my $t = ''; foreach (@$tree2) { if (! ref $_) { $t .= $_ } } },
#};
##data 254947/s   -- -30%
##bare 364383/s  43%   --

#cmpthese timethese -2, {
#    simple => sub { my $n = [1, 2, 3, "foo", 0] },
#    nested => sub { my $n = [1, 2, 3, ["foo", 0]] },
#};
##nested 511565/s     --   -34%
##simple 774699/s    51%     --

#cmpthese timethese -1, {
#    push_nested => sub { my $n = ["foo", 0]; my $a = [1, 2, 3]; push @$a, $n; $a },
#    index_nested => sub { my $n = ["foo", 0]; my $a = [1, 2, 3]; $a->[3] = $n; $a },
#    set_nested => sub { my $n = ["foo", 0];  my $a = [1, 2, 3, $n]; $a },
#    set_flat => sub { my $n = ["foo", 0]; my $a = [1, 2, 3, @$n]; $a },
#    push_flat => sub { my $n = ["foo", 0]; my $a = [1, 2, 3]; push @$a, @$n; $a },
#    splice_flat => sub { my $n = ["foo", 0]; my $a = [1, 2, 3]; splice(@$a, -1, 0, @$n); $a },
#    reverse_flat => sub { my $n = ["foo", 0]; unshift @$n, 1, 2, 3; $n },
#};
##                 Rate splice_flat push_flat index_nested push_nested set_flat set_nested reverse_flat
##splice_flat  344926/s          --       -3%         -13%        -14%     -17%       -28%         -40%
##push_flat    353975/s          3%        --         -10%        -11%     -15%       -26%         -38%
##index_nested 394568/s         14%       11%           --         -1%      -5%       -17%         -31%
##push_nested  398914/s         16%       13%           1%          --      -4%       -16%         -30%
##set_flat     416210/s         21%       18%           5%          4%       --       -13%         -27%
##set_nested   477203/s         38%       35%          21%         20%      15%         --         -17%
##reverse_flat 573917/s         66%       62%          45%         44%      38%        20%           --

{
    package Dispatch;
    sub play_Foo { my $self = shift }
    sub Foo { my $self = shift }
    no strict 'refs';
    *{__PACKAGE__.'::0'} = \&play_Foo;
}
my %DISPATCH1 = (
    Foo => sub { $_[0]->play_Foo },
);
my %DISPATCH2 = (
    Foo => [sub { $_[0]->play_Foo }],
);
my @ADISPATCH1 = ( sub { $_[0]->play_Foo } );
my @ADISPATCH2 = ( [sub { $_[0]->play_Foo }] );
my $obj = bless {}, 'Dispatch';
my $type  = 'Foo';
my $index = 0;
my $node = [$index];
my $nn = 2;
cmpthese timethese -2, {
    #dispatch1  => sub { $DISPATCH1{$type}->($obj) },
    dispatch2  => sub { $DISPATCH2{$type}->[0]->($obj) },
    #adispatch1 => sub { $ADISPATCH1[$index]->($obj) },
    adispatch2 => sub { $ADISPATCH2[$index]->[0]->($obj) },
    #table1     => sub { if ($index == 0) { $obj->play_Foo() } },
    #table2     => sub { if ($index == 1) {1} elsif ($index == 4) {1} elsif ($index == 5) {1} elsif ($index == 0) { $obj->play_Foo() } },
    method0    => sub { $obj->play_Foo() },
    method1    => sub { $obj->$type() },
    method2    => sub { my $meth = "play_$type"; $obj->$meth() },
    method3    => sub { $obj->can("play_$type")->($obj) },
    method4    => sub { $obj->$index() },
    method5    => sub { my $i = $node->[0]; $obj->$i() },
    method6    => sub { $obj->can($node->[0])->($obj) },
    method7    => sub { UNIVERSAL::can($obj, $node->[0])->($obj) },
};
exit;
#               Rate method4 method2 dispatch2 method1 table3 method3 dispatch1 table1 dispatch3 dispatch4 table2
#method4    906023/s      --    -15%      -50%    -52%   -52%    -57%      -58%   -61%      -64%      -67%   -69%
#method2   1071850/s     18%      --      -40%    -43%   -43%    -49%      -50%   -54%      -57%      -61%   -63%
#dispatch2 1798690/s     99%     68%        --     -4%    -5%    -15%      -16%   -23%      -28%      -34%   -38%
#method1   1882057/s    108%     76%        5%      --    -0%    -11%      -12%   -20%      -25%      -31%   -35%
#table3    1886049/s    108%     76%        5%      0%     --    -11%      -12%   -19%      -24%      -31%   -35%
#method3   2114065/s    133%     97%       18%     12%    12%      --       -1%   -10%      -15%      -23%   -27%
#dispatch1 2143696/s    137%    100%       19%     14%    14%      1%        --    -8%      -14%      -22%   -26%
#table1    2338579/s    158%    118%       30%     24%    24%     11%        9%     --       -6%      -15%   -20%
#dispatch3 2496610/s    176%    133%       39%     33%    32%     18%       16%     7%        --       -9%   -14%
#dispatch4 2739050/s    202%    156%       52%     46%    45%     30%       28%    17%       10%        --    -6%
#table2    2912711/s    221%    172%       62%     55%    54%     38%       36%    25%       17%        6%     --

#               Rate method4 method2 method3 dispatch2 dispatch1 method1 dispatch3
#method4    625041/s      --    -26%    -44%      -45%      -54%    -54%      -55%
#method2    847328/s     36%      --    -25%      -26%      -38%    -38%      -39%
#method3   1123939/s     80%     33%      --       -1%      -18%    -18%      -19%
#dispatch2 1137400/s     82%     34%      1%        --      -17%    -17%      -18%
#dispatch1 1366860/s    119%     61%     22%       20%        --     -0%       -2%
#method1   1367892/s    119%     61%     22%       20%        0%      --       -2%
#dispatch3 1388950/s    122%     64%     24%       22%        2%      2%        --

#sub Dispatch::play_Foo { my $self = shift }
#my %DISPATCH = (
#    Foo => \&Dispatch::play_Foo,
#);
#my $obj = bless {}, 'Dispatch';
#cmpthese timethese -1, {
#    meth => sub { $obj->play_Foo },
#    disp => sub { $DISPATCH{'Foo'}->($obj) },
#};
##          Rate disp meth
##disp 1406495/s   -- -17%
##meth 1686587/s  20%   --

#sub _shift {
#    my $self = shift;
#    my $arg1 = shift;
#    my $arg2 = shift;
#}
#sub _array {  my ($self, $arg1, $arg2) = @_; }
#sub _slice {  my ($self, $arg1, $arg2) = @_[0,1,2]; }
#sub _index {
#    my $self = $_[0];
#    my $arg1 = $_[1];
#    my $arg2 = $_[2];
#}
#cmpthese timethese -1, {
#    shift => sub { _shift(1, 2, 3) },
#    array => sub { _array(1, 2, 3) },
#    slice => sub { _slice(1, 2, 3) },
#    index => sub { _index(1, 2, 3) },
#};
##           Rate slice shift index array
##slice  983040/s    --   -5%  -17%  -17%
##shift 1037900/s    6%    --  -12%  -13%
##index 1180322/s   20%   14%    --   -1%
##array 1191563/s   21%   15%    1%    --

#use List::Util qw(first);
#my @scope = ({foo=>2},{},{bar=>3},{},{},{},{},{},{},{baz=>1});
#cmpthese timethese -1, {
#    first_foo => sub { my $ref = (first {exists $_->{foo}} @scope)->{foo} },
#    iter_foo  => sub { my $ref; for (@scope) { next if ! exists $_->{foo}; $ref = $_->{foo}; last } },
#    bare_foo  => sub { my $ref = $scope[0]->{foo} },
#    first_bar => sub { my $ref = (first {exists $_->{bar}} @scope)->{bar} },
#    iter_bar  => sub { my $ref; for (@scope) { next if ! exists $_->{bar}; $ref = $_->{bar}; last } },
#    iter_baz  => sub { my $ref; for (@scope) { next if ! exists $_->{baz}; $ref = $_->{baz}; last } },
#};
##               Rate  iter_baz first_bar first_foo  iter_bar  iter_foo  bare_foo
##iter_baz   265481/s        --      -16%      -30%      -57%      -73%      -91%
##first_bar  315077/s       19%        --      -17%      -49%      -68%      -90%
##first_foo  378300/s       42%       20%        --      -39%      -61%      -88%
##iter_bar   619376/s      133%       97%       64%        --      -36%      -80%
##iter_foo   973307/s      267%      209%      157%       57%        --      -68%
##bare_foo  3084047/s     1062%      879%      715%      398%      217%        --

#sub returnval { my ($args) = @_; return "234234234" }
#sub appendval { my ($out_ref, $args) = @_; $out_ref .= "234234234"; return }
#cmpthese timethese -1, {
#    returnval => sub { return returnval(); },
#    appendval => sub { my $out = ''; appendval(\$out); return $out },
#};
##               Rate appendval returnval
##appendval  220553/s        --      -85%
##returnval 1470359/s      567%        --

#sub returnval { my ($args) = @_; my @a = ("234234234"); return \@a }
#sub appendval { my ($tree, $args) = @_; my @a = ("234234234"); push @$tree, \@a; return 1 }
#sub returnval_false { my ($args) = @_; return undef }
#sub appendval_false { my ($tree, $args) = @_; return }
#cmpthese timethese -1, {
#    returnval        => sub { my @tree; push @tree, returnval();       return 1 if defined $tree[-1]; pop @tree; return },
#    returnval_false  => sub { my @tree; push @tree, returnval_false(); return 1 if defined $tree[-1]; pop @tree; return },
#    returnval2       => sub { my @tree; my $var = returnval();       if (defined($var)) { push @tree, $var; return 1 } return },
#    returnval_false2 => sub { my @tree; my $var = returnval_false(); if (defined($var)) { push @tree, $var; return 1 } return },
#    appendval        => sub { my @tree; return 1 if appendval(\@tree);       return },
#    appendval_false  => sub { my @tree; return 1 if appendval_false(\@tree); return },
#};
##                      Rate appendval returnval2 returnval returnval_false returnval_false2 appendval_false
##appendval         371920/s        --       -11%      -18%            -52%             -61%            -64%
##returnval2        419926/s       13%         --       -7%            -46%             -56%            -60%
##returnval         450935/s       21%         7%        --            -42%             -53%            -57%
##returnval_false   771011/s      107%        84%       71%              --             -19%            -26%
##returnval_false2  953746/s      156%       127%      112%             24%               --             -8%
##appendval_false  1041225/s      180%       148%      131%             35%               9%              --

###----------------------------------------------------------------###

sub tree_new {
    [
    "Hey bird.\n",
    [0, 2, "foo", 0],
    "Hey bird.\n",
    [3, 10, '+', [0, 2, "bar", 0], 2],
    "Hey bird.\n",
    ]
}

sub tree_old {
    [
    "Hey bird.\n",
    ['GET', 2, 3, ["foo", 0]],
    "Hey bird.\n",
    ['GET', 10, 23, [undef, '+', ["bar", 0], 2]],
    "Hey bird.\n",
    ]
}

#cmpthese timethese -2, {
#    old_build => \&tree_old,
#    new_build => \&tree_new,
#};
##              Rate old_build new_build
##old_build 138369/s        --      -20%
##new_build 172461/s       25%        --

my $tree_new = tree_new();
my $tree_old = tree_old();

#use Storable qw(freeze thaw);
#cmpthese timethese -2, {
#    old_freeze => sub { my $n = freeze $tree_old },
#    new_freeze => sub { my $n = freeze $tree_new },
#};
##              Rate old_freeze new_freeze
##old_freeze 25280/s         --        -7%
##new_freeze 27120/s         7%         --

#my $froze2 = freeze $tree_old;
#my $froze1 = freeze $tree_new;
#cmpthese timethese -2, {
#    old_thaw => sub { my $n = thaw $froze2 },
#    new_thaw => sub { my $n = thaw $froze1 },
#};
##            Rate old_thaw new_thaw
##old_thaw 77193/s       --     -11%
##new_thaw 86809/s      12%       --

###----------------------------------------------------------------###

my $DIRECTIVES = {
    GET => \&play_GET,
};

sub play_tree {
    my ($self, $tree, $out_ref) = @_;

    for my $node (@$tree) {
        if (! ref $node) {
            $$out_ref .= $node;
            next;
        }
        $$out_ref .= $self->debug_node($node) if $self->{'_debug_dirs'} && ! $self->{'_debug_off'};
        $DIRECTIVES->{$node->[0]}->($self, $node->[3], $node, $out_ref);
    }
}

sub play_GET {
    my ($self, $ident, $node, $out_ref) = @_;
    my $var = $self->play_expr($ident);
    if (defined $var) {
        $$out_ref .= $var;
    } else {
        $var = $self->undefined_get($ident, $node);
        $$out_ref .= $var if defined $var;
    }
    return;
}

sub play_expr {
    my ($self, $var, $ARGS) = @_;
    return $var if ! ref $var;
    return $self->play_operator($var) if ! $var->[0];
    my $ref =  $self->{'_vars'}->{$var->[0]};
    $ref = $self->undefined_any($var) if ! defined $ref;
    return $ref;
}

our $OPERATORS = [
    # type      precedence symbols              action (undef means play_operator will handle)
    ['left',    85,        ['+'],               sub { no warnings;     $_[0] +  $_[1]  } ],
];
our $OP_DISPATCH  = {map {my $ref = $_; map {$_ => $ref->[3]} @{$ref->[2]}} grep {$_->[3]             } @$OPERATORS};

sub play_operator {
    my ($self, $tree) = @_;
    return $OP_DISPATCH->{$tree->[1]}->(@$tree == 3 ? $self->play_expr($tree->[2]) : ($self->play_expr($tree->[2]), $self->play_expr($tree->[3])))
        if $OP_DISPATCH->{$tree->[1]};
    die;
}

###----------------------------------------------------------------###

my %OP = (
    '+' => \&operator_add,
);

sub play_tree2 {
    my ($self, $tree) = @_;
    my $out = '';
    for my $node (@$tree) {
        if (! ref $node) {
            $out .= $node;
            next;
        }
        $out .= $self->debug_node($node) if $self->{'_debug_dirs'} && ! $self->{'_debug_off'};
        if (! $node->[0]) {
            $out .= $self->play_expr2($node);
        } elsif ($node->[0] == 3) {
            $out .= $OP{$node->[2]}->($self, $node);
        } else {
            die;
        }
    }
    return $out;
}

sub play_expr2 {
    my ($self, $var, $ARGS) = @_;
    return $var if ! ref $var;
    my $ref;
    for (@{ $self->{'_scope'} }) {
        next if ! exists $_->{$var->[2]};
        $ref = $_->{$var->[2]};
        last;
    }

    if (! defined $ref) {
        if ($self->{'if_context'}) {
            $ref = $self->undefined_any($var);
        } else {
            $ref = $self->undefined_get($var);
        }
    }
    return $ref;
}

sub operator_add {
    my ($self, $node) = @_;
    no warnings;
    return $self->play_expr2($node->[3]) + $self->play_expr2($node->[4]);
}

###----------------------------------------------------------------###

my $vars = {foo => 2, bar => 3};
my $obj = bless {_vars => $vars, _scope => [$vars]}, __PACKAGE__;

sub old_method {
    my $out = '';
    $obj->play_tree($tree_old, \$out);
    $out;
}

sub new_method {
    my $out = $obj->play_tree2($tree_new);
}

print old_method();
print new_method();


cmpthese timethese -2, {
    old_play => \&old_method,
    new_play => \&new_method,
};
#            Rate old_play new_play
#old_play 50004/s       --     -20%
#new_play 62127/s      24%       --
