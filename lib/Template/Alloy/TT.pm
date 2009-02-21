package Template::Alloy::TT;

=head1 NAME

Template::Alloy::TT - Template::Toolkit role

=cut

use strict;
use warnings;

use Template::Alloy;
use Template::Alloy::Operator qw($QR_OP_ASSIGN);

our $VERSION = $Template::Alloy::VERSION;

sub new { die "This class is a role for use by packages such as Template::Alloy" }

###----------------------------------------------------------------###

sub parse_tree_tt3 {
    my $self    = shift;
    my $str_ref = shift || $self->throw('parse.no_string', "No string or undefined during parse", undef, 1);

    my $STYLE = $self->{'TAG_STYLE'} || 'default';
    local $self->{'_end_tag'}    = $self->{'END_TAG'}   || $Template::Alloy::Parse::TAGS->{$STYLE}->[1];
    local $self->{'START_TAG'}   = $self->{'START_TAG'} || $Template::Alloy::Parse::TAGS->{$STYLE}->[0];
    local $self->{'_start_tag'}  = (! $self->{'INTERPOLATE'}) ? $self->{'START_TAG'} : qr{(?: $self->{'START_TAG'} | (\$))}sx;
    local $self->{'_block_defs'} = [];

    my @tree;
    $self->parse_text($str_ref, \@tree) || return [$$str_ref];
    $self->parse_statements($str_ref, \@tree)
        || $self->throw('parse.unfinished', "Didn't make it to the end", undef, pos($$str_ref));
    #use CGI::Ex::Dump qw(debug);
    #debug \@tree;
    unshift @tree, [Template::Alloy::ID::block_def, 0, $self->{'_block_defs'}] if @{ $self->{'_block_defs'} };
    return \@tree;
}

sub Template::Alloy::parse_text {
    my ($self, $str_ref, $tree) = @_;

    $$str_ref =~ m{ \G (.*?) $self->{'_start_tag'} }gcxs || return;
    my ($text, $dollar) = ($1, $2); # dollar is set only on an interpolated var
    if ($dollar) {
        die "Not done";
    }

    ### take care of whitespace and comments flags
    my $pre_chomp = $$str_ref =~ m{ \G ([+=~-]) }gcx ? $1 : $self->{'PRE_CHOMP'};
    $pre_chomp  =~ y/-=~+/1230/ if $pre_chomp;
    if ($pre_chomp) {
        if    ($pre_chomp == 1) { $text =~ s{ (?:\n|^) [^\S\n]* \z }{}x  }
        elsif ($pre_chomp == 2) { $text =~ s{             (\s+) \z }{ }x }
        elsif ($pre_chomp == 3) { $text =~ s{             (\s+) \z }{}x  }
    }

    push @$tree, $text if length $text;
    return 1;
}

sub Template::Alloy::parse_statements {
    my ($self, $str_ref, $tree, $continue) = @_;

    $self->parse_statement($str_ref, $tree) || return if ! $continue;

    while (1) {
        my $mark = pos($$str_ref);
        my $stmt_sep = $$str_ref =~ m{ \G \s* ; }gcx ? ';' : $$str_ref =~ m{ \G \s*? \n }gcx ? "\n" : '';
        if ($self->parse_statement($str_ref, $tree)) {
            if ($stmt_sep ne ';') {
                if ($self->{'SEMICOLONS'}) {
                    $self->throw('parse', "Missing semi-colon with SEMICOLONS => 1", undef, pos($$str_ref));
                } elsif ($stmt_sep ne "\n") {
                    $self->throw('parse', "Individual expressions must be separated by a semicolon or a newline", undef, pos($$str_ref));
                }
            }
            next;
        }

        if ($$str_ref =~ m{ \G \s* ([+=~-]?) $self->{'_end_tag'} }gcxs) {
            my $post_chomp = $1 || $self->{'POST_CHOMP'};
            $post_chomp =~ y/-=~+/1230/ if $post_chomp;
            my $eot;
            if (! $self->parse_text($str_ref, $tree)) {
                $$str_ref =~ m{ \G (.*) }xgcs;
                push @$tree, $1 if length($1);
                $eot = 1;
            }
            if ($post_chomp && length $tree->[-1]) {
                if    ($post_chomp == 1) { $tree->[-1] =~ s{ ^ [^\S\n]* \n }{}x  }
                elsif ($post_chomp == 2) { $tree->[-1] =~ s{ ^ \s+         }{ }x }
                elsif ($post_chomp == 3) { $tree->[-1] =~ s{ ^ \s+         }{}x  }
            }
            return 1 if $eot;
            $self->parse_statement($str_ref, $tree) || return;
            next;
        }
        $self->throw('parse', 'Not sure what to do next', undef, pos($$str_ref));
    }
    return;
}

sub Template::Alloy::parse_statement {
    my ($self, $str_ref, $tree) = @_;
    $$str_ref =~ m{ \G \s* }gcx;

    if ($$str_ref =~ m{ \G (?:GET|get) \b }gcx) {
        $self->parse_expr_new($str_ref, $tree); # || die "Missing expr";
    } elsif ($$str_ref =~ m{ \G (?:SET|set) \b }gcx) {
        while (1) {
            my $pos = pos($$str_ref) - 3;
            $self->parse_expr_new($str_ref, $tree) || last;
            if ($tree->[-1]->[0] != 2) {
                my $var = $tree->[-1];
                $tree->[-1] = [2, $pos, $var, [99]];
            }
        }
    } elsif ($$str_ref =~ m{ \G (?:CALL|call) \b }gcx) {
        my @var = (Template::Alloy::ID::call, pos($$str_ref) - 4);
        push @$tree, \@var;
        $self->parse_expr_new($str_ref, \@var) || $self->throw('parse', 'Missing expr in CALL directive', undef, pos($$str_ref));

    } elsif ($$str_ref =~ m{ \G (?:BLOCK|block) \b }gcx) {
        my @var = (Template::Alloy::ID::tree, pos($$str_ref) - 5);
        my $name;
        if ($$str_ref =~ m{ \G \s* ($Template::Alloy::Parse::QR_FILENAME) }gcx) {
            $name = $1;
        } elsif ($$str_ref =~ m{ \G \s* ($Template::Alloy::Parse::QR_BLOCK) }gcx) {
            $name = $1;
        } elsif ($self->parse_expr_new($str_ref, my $cap = [])) {
            $name = $cap->[0];
            $self->throw('parse', 'BLOCK name must be a filename, blockname, or literal string') if ref $name;
        } else {
            $name = '';
        }

        my @tree;
        local $self->{'_block_name'} = [@{ $self->{'_block_name'} || []}];
        push @{ $self->{'_block_name'} }, $name;
        $name = join '/', @{ $self->{'_block_name'} };
        eval { $self->parse_statements($str_ref, \@tree, 1) };
        if (my $err = $@) {
            die $err if ! UNIVERSAL::can($err, 'type') || $err->type ne 'parse.end';
            push @{ $self->{'_block_defs'} }, [$name, \@tree];
            return 1;
        }
        $self->throw('parse', 'Missing END tag', undef, pos($$str_ref));

    } elsif ($$str_ref =~ m{ \G (?:PROCESS|process) \b }gcx) {
        my $pos = pos($$str_ref) - 7;
        my $name;
        if ($$str_ref =~ m{ \G \s* ($Template::Alloy::Parse::QR_FILENAME) }gcx) {
            $name = $1;
        } elsif ($$str_ref =~ m{ \G \s* ($Template::Alloy::Parse::QR_BLOCK) }gcx) {
            $name = $1;
        } elsif ($self->parse_expr_new($str_ref, my $cap = [])) {
            $name = $cap->[0];
            $self->throw('parse', 'BLOCK name must be a filename, blockname, or literal string') if ref $name;
        } else {
            $self->throw('parse', 'Missing filename or block name in PROCESS');
        }
        push @$tree, [Template::Alloy::ID::process, $pos, [$name]];
        return 1;

    } elsif ($$str_ref =~ m{ \G (?:END|end) \b }gcx) {
        $self->throw('parse.end', "END tag found", undef, pos($$str_ref));
    } else {
        $self->parse_expr_new($str_ref, $tree) || return;
    }
    return 1;
}

sub Template::Alloy::parse_expr_new {
    my ($self, $str_ref, $tree) = @_;
    $self->parse_variable($str_ref, $tree) || return;

    if ($self->{'allow =>'} && $$str_ref =~ m{ \G \s* (?= =>) \s* }gcx) { # fake precedence here # autoquote
        return 1;
    }

    my @other;
    my $found;
    while (1) {
        if ($self->{'_end_tag'} && $$str_ref =~ m{ \G ( \s* [+=~-]? $self->{'_end_tag'} ) }gcx) {
            pos($$str_ref) = pos($$str_ref) - length($1);
            last;
        }
        last if $$str_ref !~ m{ \G \s* ($Template::Alloy::Operator::QR_OP) }gcxo;

        #if ($Template::Alloy::Operator::OP_ASSIGN->{$1} && ! $ARGS->{'allow_parened_ops'}) { # only allow assignment in parens
        #    pos($$str_ref) = $mark;
        #    last;
        #}
        my $op = $1;
        $op = 'eq' if $op eq '==' && (! defined($self->{'V2EQUALS'}) || $self->{'V2EQUALS'});
        $op = 'ne' if $op eq '!=' && (! defined($self->{'V2EQUALS'}) || $self->{'V2EQUALS'});
        push @other, pos($$str_ref) - length($op), $op;
        #print "((($op)))\n";

        ### allow for postfix - doesn't check precedence - someday we might change - but not today (only affects post ++ and --)
        if ($Template::Alloy::Operator::OP_POSTFIX->{$op}) {
            die "Not done yet";
            #$var = [[undef, $op, $var, 1], 0]; # cheat - give a "second value" to postfix ops
            next;

        #### allow for prefix operator precedence
        #} elsif ($has_prefix && $OP->{$op}->[1] < $OP_PREFIX->{$has_prefix->[-1]}->[1]) {
        #    if ($tree) {
        #        if ($#$tree == 1) { # only one operator - keep simple things fast
        #            $var = [[undef, $tree->[0], $var, $tree->[1]], 0];
        #        } else {
        #            unshift @$tree, $var;
        #            $var = $self->apply_precedence($tree, $found, $str_ref);
        #        }
        #        undef $tree;
        #        undef $found;
        #    }
        #    $var = [[undef, $has_prefix->[-1], $var ], 0];
        #    pop @$has_prefix;
        #    $has_prefix = undef if ! @$has_prefix;
        }

        ### add the operator to the tree
        $self->parse_variable($str_ref, \@other)
            || $self->throw('parse', 'Missing variable after "'.$op.'"', undef, pos($$str_ref));
        $found->{$Template::Alloy::Operator::OP->{$op}->[1]}->{$op} = 1; # found->{precedence}->{op}
    }

    ### if we found operators - tree the nodes by operator precedence
    if (@other) {
        if (@other == 3) { # only one operator - keep simple things fast
            if ($Template::Alloy::Operator::OP->{$other[1]}->[0] eq 'assign'
                && $other[1] =~ /(.+)=/) {
                my $prev_expr = $tree->[-1];
                $tree->[-1] = [2, $other[0], $prev_expr, [5, $other[0], $1, $prev_expr, $other[2]]];
                #$var = [[undef, '=', $var, [[undef, $1, $var, $tree->[1]], 0]], 0]; # "a += b" => "a = a + b"
            } else {
                my $prev_expr = $tree->[-1];
                if ($other[1] eq '=') {
                    $tree->[-1] = [2, $other[0], $prev_expr, $other[2]];
                } else {
                    $tree->[-1] = [5, $other[0], $other[1], $prev_expr, $other[2]];
                }
            }
        } else {
            unshift @other, $tree->[-1];
            $tree->[-1] = $self->apply_precedence2(\@other, $found, $str_ref);
        }
    }

    #### allow for prefix on non-chained variables
    #if ($has_prefix) {
    #    $var = [[undef, $_, $var], 0] for reverse @$has_prefix;
    #}

    return 1;
}

### this is used to put the parsed variables into the correct operations tree
sub Template::Alloy::apply_precedence2 {
    my ($self, $tree, $found, $str_ref) = @_;

    my @var;
    my $trees;
    ### look at the operators we found in the order we found them
    for my $prec (sort keys %$found) {
        my $ops = $found->{$prec};
        local $found->{$prec};
        delete $found->{$prec};

        use CGI::Ex::Dump qw(debug);
        ### split the array on the current operators for this level
        my @ops;
        my @loc;
        my @exprs;
        for (my $i = 2; $i <= $#$tree; $i += 3) { # [23 2 + 24 8 + 25]
            next if ! $ops->{ $tree->[$i] };
            push @ops,   $tree->[$i];
            push @exprs, [splice @$tree, 0, $i, ()];
            push @loc,   pop(@{ $exprs[-1] });
            shift @$tree;
            $i = -1;
        }
        next if ! @exprs; # this iteration didn't have the current operator
        push @exprs, $tree if scalar @$tree; # add on any remaining items

        ### simplify sub expressions
        for my $node (@exprs) {
            if (@$node == 1) {
                $node = $node->[0]; # single item - its not a tree
            } elsif (@$node == 3) {
                die "Single operator";
                $node = [[undef, $node->[1], $node->[0], $node->[2]], 0]; # single operator - put it straight on
            } else {
                $node = $self->apply_precedence2($node, $found, $str_ref); # more complicated - recurse
            }
        }

        ### assemble this current level

        ### some rules:
        # 1) items at the same precedence level must all be either right or left or ternary associative
        # 2) ternary items cannot share precedence with anybody else.
        # 3) there really shouldn't be another operator at the same level as a postfix
        my $type = $Template::Alloy::Operator::OP->{$ops[0]}->[0];

        if ($type eq 'ternary') {
            my $op = $Template::Alloy::Operator::OP->{$ops[0]}->[2]->[0]; # use the first op as what we are using

            ### return simple ternary
            if (@exprs == 3) {
                $self->throw('parse', "Ternary operator mismatch", undef, pos($$str_ref)) if $ops[0] ne $op;
                $self->throw('parse', "Ternary operator mismatch", undef, pos($$str_ref)) if ! $ops[1] || $ops[1] eq $op;
                return [5, $loc[0], $op, @exprs];
            }

            ### reorder complex ternary - rare case
            while ($#ops >= 1) {
                ### if we look starting from the back - the first lead ternary op will always be next to its matching op
                for (my $i = $#ops; $i >= 0; $i--) {
                    next if $Template::Alloy::Operator::OP->{$ops[$i]}->[2]->[1] eq $ops[$i];
                    my ($op, $op2) = splice @ops, $i, 2, (); # remove the pair of operators
                    my $node = [5, $loc[$i], $op, @exprs[$i .. $i + 2]];
                    splice @exprs, $i, 3, $node;
                }
            }
            return $exprs[0]; # at this point the ternary has been reduced to a single operator

        } elsif ($type eq 'right' || $type eq 'assign') {
            my $val = $exprs[-1];
            for (reverse (0 .. $#exprs - 1)) {
                if ($type eq 'assign' && $ops[$_ - 1] =~ /(.+)=$/) {
                    die "Complex assign";
                    $val = [[undef, '=', $exprs[$_], [[undef, $1, $exprs[$_], $val], 0]], 0];
                } else {
                    $val = [5, $loc[$_ - 1], $ops[$_ - 1], $exprs[$_], $val];
                }
            }
            return $val;

        } else {
            my $val = $exprs[0];
            $val = [5, $loc[$_ - 1], $ops[$_ - 1], $val, $exprs[$_]] for (1 .. $#exprs);
            return $val;

        }
    }

    $self->throw('parse', "Couldn't apply precedence", undef, pos($$str_ref));
}

sub Template::Alloy::parse_variable {
    my ($self, $str_ref, $tree) = @_;
    $$str_ref =~ m{ \G \s* }gcxo;

    my $is_literal;

    if ($$str_ref =~ m{ \G \s* ([^\W\d]\w*\b) (?<! qw \b) }gcx) { # [% foo %]
        my @var = (Template::Alloy::ID::expr, pos($$str_ref) - length($1), $1);
        push @$tree, \@var;

        $self->parse_function_args($str_ref, \@var);       # [% foo('bar') %]
        1 while $self->parse_var_postfix($str_ref, \@var); # [% foo.bar %]
        return 1;
    } elsif ($$str_ref =~ m{ \G \s* ([@\$]?) \( }gcx) {                  # [% (foo) %]
        my $ctx = $1;
        my $pos = pos($$str_ref) - 1 - length($ctx);
        my @args;
        1 while $self->parse_statement($str_ref, \@args) && $$str_ref =~ m{ \G \s* ; }gcx;
        $$str_ref =~ m{ \G \s* \) }gcx || $self->throw('parse', "Missing close ')'", undef, pos($$str_ref));
        $$str_ref =~ m{ \G \( }gcx && $self->throw('parse', "Close ) cannot be followed by function args", undef, pos($$str_ref));
        my @var = (Template::Alloy::ID::expr, $pos, [!$ctx         ? Template::Alloy::ID::tree
                                                     : $ctx eq '$' ? Template::Alloy::ID::tree_item
                                                     :               Template::Alloy::ID::tree_list, $pos, \@args]);
        push @var, 0; #$self->parse_function_args($str_ref, \@var);
        1 while $self->parse_var_postfix($str_ref, \@var);
        push @$tree, \@var;
        return 1;
    } elsif ($$str_ref =~ m{ \G \s* \$ }gcx) {                   # [% $foo %]
        my @var = (Template::Alloy::ID::named_expr, pos($$str_ref));
        if ($$str_ref =~ m{ \G ([^\W\d]\w*) }gcx) {
            push @var, [Template::Alloy::ID::expr, pos($$str_ref) - length($1), $1, 0];
        } elsif ($$str_ref =~ m{ \G \{ }gcx) {
            $self->parse_expr_new($str_ref, \@var) || $self->throw('parse', 'Missing expression after \${', undef, pos $$str_ref);
            $$str_ref =~ m{ \G \s* \} }gcx || $self->throw('parse', 'Missing close }', undef, pos $$str_ref);
        } else {
            $self->throw('parse', 'Invalid character following $', undef, pos($$str_ref));
        }
        push @$tree, \@var;
        $self->parse_function_args($str_ref, \@var);
        1 while $self->parse_var_postfix($str_ref, \@var);
        return 1;
    } elsif ($$str_ref =~ m{ \G / }gcx) {
        my $pos = pos($$str_ref) - 1;
        $$str_ref =~ m{ \G (.*?) (?<! \\) / ([msixeg]*) }gcxs
            || $self->throw('parse', 'Unclosed regex tag "/"', undef, pos($$str_ref));
        my ($str, $opts) = ($1, $2);
        $self->throw('parse', 'e option not allowed on regex',   undef, pos($$str_ref)) if $opts =~ /e/;
        $self->throw('parse', 'g option not supported on regex', undef, pos($$str_ref)) if $opts =~ /g/;
        $str =~ s|\\n|\n|g;
        $str =~ s|\\t|\t|g;
        $str =~ s|\\r|\r|g;
        $str =~ s|\\\/|\/|g;
        $str =~ s|\\\$|\$|g;
        $self->throw('parse', "Invalid regex: $@", undef, pos($$str_ref)) if ! eval { "" =~ /$str/; 1 };
        push @$tree, [Template::Alloy::ID::regex, $pos, $str, $opts];
        return 1;
    }

    my @var = (Template::Alloy::ID::expr, pos($$str_ref));
    if ($self->parse_number($str_ref, \@var)
        || $self->parse_quoted_single($str_ref, \@var)
        || $self->parse_quoted_double($str_ref, \@var)
        ) {
        push @var, 0;
        if ($self->parse_var_postfix($str_ref, \@var, 1)) { # autoboxed
            1 while $self->parse_var_postfix($str_ref, \@var);
            push @$tree, \@var;
        } else {
            push @$tree, $var[2];
        }
        return 1;
    }

    if ($self->parse_constr_list($str_ref, \@var)
        || $self->parse_constr_hash($str_ref, \@var)) {
        if ($self->parse_var_postfix($str_ref, \@var)) { # autoboxed
            1 while $self->parse_var_postfix($str_ref, \@var);
            push @$tree, \@var;
        } else {
            push @$tree, $var[2];
        }
        return 1;
    }

    return;
}

sub Template::Alloy::parse_constr_list {
    my ($self, $str_ref, $var) = @_;
    if ($$str_ref =~ m{ \G \s* \[ }gcx) {
        my @args = (Template::Alloy::ID::list, pos($$str_ref) - 1);
        $$str_ref =~ m{ \G \s* , }gcx while $self->parse_expr_new($str_ref, \@args);
        $$str_ref =~ m{ \G \s* \] }gcx || $self->throw('parse.missing', "Missing close ']'", undef, pos($$str_ref));
        push @$var, \@args, 0;
        return 1;
    } elsif ($$str_ref =~ m{ \G \s* qw ([^\w\s]) \s* }gcx) {
        my $quote = $1;
        $quote =~ y|([{<|)]}>|;
        $$str_ref =~ m{ \G (.*?) (?<!\\) \Q$quote\E }gcxs
            || $self->throw('parse.missing.array_close', "Missing close \"$quote\"", undef, pos($$str_ref));
        my $str = $1;
        $str =~ s{ ^ \s+ }{}x;
        $str =~ s{ \s+ $ }{}x;
        $str =~ s{ \\ \Q$quote\E }{$quote}gx;
        push @$var, [Template::Alloy::ID::list, undef, split /\s+/, $str], 0;
        return 1;
    }
    return;
}

sub Template::Alloy::parse_constr_hash {
    my ($self, $str_ref, $var) = @_;
    $$str_ref =~ m{ \G \s* \{ }gcx || return;
    my @args = (Template::Alloy::ID::hash, pos($$str_ref) - 1);
    local $self->{'allow =>'} = 1;
    while (1) {
        $self->parse_expr_new($str_ref, \@args) || last;
        if ($$str_ref =~ m{ \G \s* => }gcx) { # autoquote - turned named access back into direct varname
            $args[-1] = $args[-1]->[2] if ref($args[-1]) && ! $args[-1]->[0] && ! $args[-1]->[3];
            $args[-1]->[0] = Template::Alloy::ID::expr if ref($args[-1]) && $args[-1]->[0] == Template::Alloy::ID::named_expr;
        #$self->parse_variable($str_ref, $tree) || push @$tree, [99, pos($$str_ref)];
        } else {
            $$str_ref =~ m{ \G \s* , }gcx;
        }
    }
    $$str_ref =~ m{ \G \s* \} }gcx || $self->throw('parse.missing', "Missing close '}'", undef, pos($$str_ref));
    push @$var, \@args, 0;
    return 1;
}

sub Template::Alloy::parse_number {
    my ($self, $str_ref, $var) = @_;
    $$str_ref =~ m{ \G \s* ( -? $Template::Alloy::Parse::QR_NUM ) }gcxo || return;
    push @$var, 0 + $1;
    return 1;
}

sub Template::Alloy::parse_quoted_single {
    my ($self, $str_ref, $var) = @_;
    $$str_ref =~ m{ \G \s* \' (.*?) (?<! \\) \' }gcxs || return;
    my $str = $1;
    $str =~ s{ \\\' }{\'}xg;
    push @$var, $str;
    return 1;
}

sub Template::Alloy::parse_quoted_double {
    my ($self, $str_ref, $var) = @_;
    $$str_ref =~ m{ \G \s* \" }gcx || return;
    my @pieces;
    while ($$str_ref =~ m{ \G (.*?) ([\"\$\\]) }gcxs) {
        my ($str, $item) = ($1, $2);
        if (length $str) {
            if (defined($pieces[-1]) && ! ref($pieces[-1])) { $pieces[-1] .= $str; } else { push @pieces, $str }
        }
        if ($item eq '\\') {
            die;
            #my $chr = ($$str_ref =~ m{ \G ($QR_ESCAPES) }gcxo) ? $_escapes->{$1} : '\\';
            #if (defined($pieces[-1]) && ! ref($pieces[-1])) { $pieces[-1] .= $chr; } else { push @pieces, $chr }
            #next;
        } elsif ($item eq '"') {
            last;
        } elsif ($self->{'AUTO_EVAL'}) {
            die;
            if (defined($pieces[-1]) && ! ref($pieces[-1])) { $pieces[-1] .= '$'; } else { push @pieces, '$' }
            next;
        }
        # dollar
        my $not  = $$str_ref =~ m{ \G ! }gcx; # primarily for velocity
        my $mark = pos($$str_ref);
        if ($$str_ref =~ m{ \G ([^\W\d]\w*) }gcx) {
            push @pieces, [Template::Alloy::ID::expr, pos($$str_ref) - length($1), $1, 0];
        } elsif ($$str_ref =~ m{ \G \{ }gcx) {
            $self->parse_expr_new($str_ref, \@pieces);
            $$str_ref =~ m{ \G \s* \} }gcx || $self->throw('parse', 'Missing close }', undef, pos($$str_ref));
        } else {
            $self->throw('parse', 'Invalid character following $', undef, pos($$str_ref));
        }
        if (! $not && $self->{'SHOW_UNDEFINED_INTERP'}) {
            die;
        #    $ref = [[undef, '//', $ref, '$'.substr($$str_ref, $mark, pos($$str_ref)-$mark)], 0];
        }
    }
    if (! @pieces) { # [% "" %]
        push @$var, '';
        return 1;
    } elsif (@pieces == 1 && ! ref $pieces[0]) {
        push @$var, $pieces[0];
        return 1;
    } else {
        push @$var, [Template::Alloy::ID::tree, undef, \@pieces];
        return 1;
    }
    #} elsif (@pieces == 1 && ref $pieces[0]) { # [% "$foo" %] or [% "${ 1 + 2 }" %]
    #    push @$var, $pieces[0];
    #    return 1;
    #} elsif ($self->{'AUTO_EVAL'}) {
    #    die;
    #    #push @var, [undef, '~', @pieces], 0, '|', 'eval', 0;
    #    #return \@var if $is_aq;
    #} elsif (@pieces == 1) { # [% "foo" %]
    #    push @$var, $pieces[0];
    #    return 1;
    #} else { # [% "foo $bar baz" %]
    #    push @$var, [Template::Alloy::ID::tree, undef, \@pieces];
    #    return 1;
    #}
    return;
}

sub Template::Alloy::parse_function_args {
    my ($self, $str_ref, $var) = @_;
    if ($$str_ref =~ m{ \G \( }gcx) {
        my @args;
        $$str_ref =~ m{ \G \s* , }gcx while $self->parse_expr_new($str_ref, \@args);
        $$str_ref =~ m{ \G \s* \) }gcx || $self->throw('parse.missing', "Missing close ')'", undef, pos($$str_ref));
        push @$var, \@args;
    } else {
        push @$var, 0;
    }
    return 1;
}

sub Template::Alloy::parse_var_postfix {
    my ($self, $str_ref, $var, $is_literal) = @_;
    if ($$str_ref =~ m{ \G \s* \| (?! \|) }gcx) {
        $var->[2] = [Template::Alloy::ID::tree, $var->[1], [$var->[2]]] if $is_literal;
        my @copy = @$var;
        @$var = (Template::Alloy::ID::filter, pos($$str_ref) - 1, \@copy);
    } else {
        $$str_ref =~ m{ \G \s* \. (?! \.) }gcx || return;
        $var->[2] = [Template::Alloy::ID::tree, $var->[1], [$var->[2]]] if $is_literal;
    }
    if ($$str_ref =~ m{ \G \s* ( [^\W\d]\w* ) }gcx) {
        push @$var, $1;
    } elsif ($$str_ref =~ m{ \G \s* ( -? \d+ ) }gcx) {
        push @$var, $1;
    } elsif ($$str_ref =~ m{ \G \s* \$ }gcx) {
        if ($$str_ref =~ m{ \G ([^\W\d]\w*) }gcx) {
            push @$var, [Template::Alloy::ID::expr, pos($$str_ref) - length($1), $1, 0];
        } elsif ($$str_ref =~ m{ \G \{ }gcx) {
            $self->parse_expr_new($str_ref, $var) || $self->throw('parse', 'Missing expression after \${', undef, pos $$str_ref);
            $$str_ref =~ m{ \G \s* \} }gcx || $self->throw('parse', 'Missing close }', undef, pos $$str_ref);
        } else {
            $self->throw('parse', 'Invalid character following $', undef, pos($$str_ref));
        }
    } elsif ($$str_ref =~ m{ \G \[ }gcx) {
        $self->parse_expr_new($str_ref, $var) || $self->throw('parse', 'Missing expression after [', undef, pos $$str_ref);
        $$str_ref =~ m{ \G \s* \] }gcx || $self->throw('parse', 'Missing close ]', undef, pos $$str_ref);
    } else {
        $self->throw('parse.missing', "Missing identifier", undef, pos($$str_ref));
    }
    $self->parse_function_args($str_ref, $var);
    return 1;
}

sub parse_tree_tt33 {
    my $self    = shift;
    my $str_ref = shift;
    my $one_tag_only = shift() ? 1 : 0;
    if (! $str_ref || ! defined $$str_ref) {
        $self->throw('parse.no_string', "No string or undefined during parse", undef, 1);
    }

    my $STYLE = $self->{'TAG_STYLE'} || 'default';
    local $self->{'_end_tag'}   = $self->{'END_TAG'}   || $Template::Alloy::Parse::TAGS->{$STYLE}->[1];
    local $self->{'START_TAG'}  = $self->{'START_TAG'} || $Template::Alloy::Parse::TAGS->{$STYLE}->[0];
    local $self->{'_start_tag'} = (! $self->{'INTERPOLATE'}) ? $self->{'START_TAG'} : qr{(?: $self->{'START_TAG'} | (\$))}sx;

    our $QR_COMMENTS ||= $Template::Alloy::Parse::QR_COMMENTS; # must be our because we localise later on
    my $dirs    = $Template::Alloy::Parse::DIRECTIVES;
    my $aliases = $Template::Alloy::Parse::ALIASES;
    local @{ $dirs }{ keys %$aliases } = values %$aliases; # temporarily add to the table
    local @{ $self }{@Template::Alloy::CONFIG_COMPILETIME} = @{ $self }{@Template::Alloy::CONFIG_COMPILETIME};

    my @tree;             # the parsed tree
    my $pointer = \@tree; # pointer to current tree to handle nested blocks
    my @state;            # maintain block levels
    local $self->{'_state'} = \@state; # allow for items to introspect (usually BLOCKS)
    local $self->{'_no_interp'} = 0;   # no interpolation in some blocks (usually PERL)
    my @in_view;          # let us know if we are in a view
    my @blocks;           # store blocks for later moving to front
    my @meta;             # place to store any found meta information (to go into META)
    my $post_chomp = 0;   # previous post_chomp setting
    my $continue   = 0;   # flag for multiple directives in the same tag
    my $post_op    = 0;   # found a post-operative DIRECTIVE
    my $capture;          # flag to start capture
    my $func;
    my $node;
    pos($$str_ref) = 0 if ! $one_tag_only;

    while (1) {
        ### continue looking for information in a semi-colon delimited tag
        if ($continue) {
            $node = [undef, $continue, undef];

        } elsif ($one_tag_only) {
            $node = [undef, pos($$str_ref), undef];

        ### find the next opening tag
        } else {
            $$str_ref =~ m{ \G (.*?) $self->{'_start_tag'} }gcxs
                || last;
            my ($text, $dollar) = ($1, $2); # dollar is set only on an interpolated var

            ### found a text portion - chomp it and store it
            if (length $text) {
                if (! $post_chomp) { }
                elsif ($post_chomp == 1) { $text =~ s{ ^ [^\S\n]* \n }{}x  }
                elsif ($post_chomp == 2) { $text =~ s{ ^ \s+         }{ }x }
                elsif ($post_chomp == 3) { $text =~ s{ ^ \s+         }{}x  }
                push @$pointer, $text if length $text;
            }

            ### handle variable interpolation ($2 eq $)
            if ($dollar) {
                ### inspect previous text chunk for escape slashes
                my $n = ($text =~ m{ (\\+) $ }x) ? length($1) : 0;
                if ($self->{'_no_interp'} || $n % 2) { # were there odd escapes
                    my $prev_text;
                    $prev_text = \$pointer->[-1] if defined($pointer->[-1]) && ! ref($pointer->[-1]);
                    chop($$prev_text) if $n % 2;
                    if ($prev_text) { $$prev_text .= $dollar } else { push @$pointer, $dollar }
                    next;
                }

                my $not  = $$str_ref =~ m{ \G ! }gcx;
                my $mark = pos($$str_ref);
                my $ref;
                if ($$str_ref =~ m{ \G \{ }gcx) {
                    local $self->{'_operator_precedence'} = 0; # allow operators
                    $ref = $self->parse_expr($str_ref);
                    $$str_ref =~ m{ \G \s* $QR_COMMENTS \} }gcxo
                        || $self->throw('parse', 'Missing close }', undef, pos($$str_ref));
                } else {
                    local $self->{'_operator_precedence'} = 1; # no operators
                    local $QR_COMMENTS = qr{};
                    $ref = $self->parse_expr($str_ref);
                }
                $self->throw('parse', "Error while parsing for interpolated string", undef, pos($$str_ref))
                    if ! defined $ref;
                if (! $not && $self->{'SHOW_UNDEFINED_INTERP'}) {
                    $ref = [[undef, '//', $ref, '$'.substr($$str_ref, $mark, pos($$str_ref)-$mark)], 0];
                }
                push @$pointer, ['GET', $mark, pos($$str_ref), $ref];
                $post_chomp = 0; # no chomping after dollar vars
                next;
            }

            $node = [undef, pos($$str_ref), undef];

            ### take care of whitespace and comments flags
            my $pre_chomp = $$str_ref =~ m{ \G ([+=~-]) }gcx ? $1 : $self->{'PRE_CHOMP'};
            $pre_chomp  =~ y/-=~+/1230/ if $pre_chomp;
            if ($pre_chomp && $pointer->[-1] && ! ref $pointer->[-1]) {
                if    ($pre_chomp == 1) { $pointer->[-1] =~ s{ (?:\n|^) [^\S\n]* \z }{}x  }
                elsif ($pre_chomp == 2) { $pointer->[-1] =~ s{             (\s+) \z }{ }x }
                elsif ($pre_chomp == 3) { $pointer->[-1] =~ s{             (\s+) \z }{}x  }
                splice(@$pointer, -1, 1, ()) if ! length $pointer->[-1]; # remove the node if it is zero length
            }

            ### leading # means to comment the entire section
            if ($$str_ref =~ m{ \G \# }gcx) {
                $$str_ref =~ m{ \G (.*?) ([+~=-]?) ($self->{'_end_tag'}) }gcxs # brute force - can't comment tags with nested %]
                    || $self->throw('parse', "Missing closing tag", undef, pos($$str_ref));
                $node->[0] = '#';
                $node->[2] = pos($$str_ref) - length($3) - length($2);
                push @$pointer, $node;

                $post_chomp = $2;
                $post_chomp ||= $self->{'POST_CHOMP'};
                $post_chomp =~ y/-=~+/1230/ if $post_chomp;
                next;
            }
            #$$str_ref =~ m{ \G \s* $QR_COMMENTS }gcxo;
        }

        ### look for DIRECTIVES
        if ($$str_ref =~ m{ \G \s* $QR_COMMENTS $Template::Alloy::Parse::QR_DIRECTIVE }gcxo   # find a word
            && ($func = $self->{'ANYCASE'} ? uc($1) : $1)
            && ($dirs->{$func}
                || ((pos($$str_ref) -= length $1) && 0))
            ) {                       # is it a directive
            $$str_ref =~ m{ \G \s* $QR_COMMENTS }gcx;

            $func = $aliases->{$func} if $aliases->{$func};
            $node->[0] = $func;

            ### store out this current node level to the appropriate tree location
            # on a post operator - replace the original node with the new one - store the old in the new
            if ($dirs->{$func}->[3] && $post_op) {
                my @post_op = @$post_op;
                @$post_op = @$node;
                $node = $post_op;
                $node->[4] = [\@post_op];
            # if there was not a semi-colon - see if semis were required
            } elsif ($post_op && $self->{'SEMICOLONS'}) {
                $self->throw('parse', "Missing semi-colon with SEMICOLONS => 1", undef, $node->[1]);

            # handle directive captures for an item like "SET foo = BLOCK"
            } elsif ($capture) {
                push @{ $capture->[4] }, $node;
                undef $capture;

            # normal nodes
            } else{
                push @$pointer, $node;
            }

            ### parse any remaining tag details
            $node->[3] = eval { $dirs->{$func}->[0]->($self, $str_ref, $node) };
            if (my $err = $@) {
                $err->node($node) if UNIVERSAL::can($err, 'node') && ! $err->node;
                die $err;
            }
            $node->[2] = pos $$str_ref;

            ### anything that behaves as a block ending
            if ($func eq 'END' || $dirs->{$func}->[4]) { # [4] means it is a continuation block (ELSE, CATCH, etc)
                if (! @state) {
                    $self->throw('parse', "Found an $func tag while not in a block", $node, pos($$str_ref));
                }
                my $parent_node = pop @state;

                if ($func ne 'END') {
                    pop @$pointer; # we will store the node in the parent instead
                    $parent_node->[5] = $node;
                    my $parent_type = $parent_node->[0];
                    if (! $dirs->{$func}->[4]->{$parent_type}) {
                        $self->throw('parse', "Found unmatched nested block", $node, pos($$str_ref));
                    }
                }

                ### restore the pointer up one level (because we hit the end of a block)
                $pointer = (! @state) ? \@tree : $state[-1]->[4];

                ### normal end block
                if ($func eq 'END') {
                    if ($parent_node->[0] eq 'BLOCK') { # move BLOCKS to front
                        if (defined($parent_node->[3]) && @in_view) {
                            push @{ $in_view[-1] }, $parent_node;
                        } else {
                            push @blocks, $parent_node;
                        }
                        if ($pointer->[-1] && ! $pointer->[-1]->[6]) {
                            splice(@$pointer, -1, 1, ());
                        }
                    } elsif ($parent_node->[0] eq 'VIEW') {
                        my $ref = { map {($_->[3] => $_->[4])} @{ pop @in_view }};
                        unshift @{ $parent_node->[3] }, $ref;
                    } elsif ($dirs->{$parent_node->[0]}->[5]) { # allow no_interp to turn on and off
                        $self->{'_no_interp'}--;
                    }

                ### continuation block - such as an elsif
                } else {
                    push @state, $node;
                    $pointer = $node->[4] ||= [];
                }

            ### handle block directives
            } elsif ($dirs->{$func}->[2] && ! $post_op) {
                    push @state, $node;
                    $pointer = $node->[4] ||= []; # allow future parsed nodes before END tag to end up in current node
                    push @in_view, [] if $func eq 'VIEW';
                    $self->{'_no_interp'}++ if $dirs->{$node->[0]}->[5] # allow no_interp to turn on and off

            } elsif ($func eq 'TAGS') {
                ($self->{'_start_tag'}, $self->{'_end_tag'}, my $old_end) = (@{ $node->[3] }[0,1], $self->{'_end_tag'});

                ### allow for one more closing tag of the old style
                if ($$str_ref =~ m{ \G \s* $QR_COMMENTS ([+~=-]?) $old_end }gcxs) {
                    $post_chomp = $1 || $self->{'POST_CHOMP'};
                    $post_chomp =~ y/-=~+/1230/ if $post_chomp;
                    $continue = 0;
                    $post_op  = 0;
                    next;
                }

            } elsif ($func eq 'META') {
                unshift @meta, %{ $node->[3] }; # first defined win
                $node->[3] = undef;             # only let these be defined once - at the front of the tree
            }

        ### allow for bare variable getting and setting
        } elsif (defined(my $var = $self->parse_expr($str_ref))) {
            if ($post_op && $self->{'SEMICOLONS'}) {
                $self->throw('parse', "Missing semi-colon with SEMICOLONS => 1", undef, $node->[1]);
            }
            push @$pointer, $node;
            if ($$str_ref =~ m{ \G \s* $QR_COMMENTS ($QR_OP_ASSIGN) >? (?! [+=~-]? $self->{'_end_tag'}) \s* $QR_COMMENTS }gcx) {
                $node->[0] = 'SET';
                $node->[3] = eval { $dirs->{'SET'}->[0]->($self, $str_ref, $node, $1, $var) };
                if (my $err = $@) {
                    $err->node($node) if UNIVERSAL::can($err, 'node') && ! $err->node;
                    die $err;
                }
            } else {
                $node->[0] = 'GET';
                $node->[3] = $var;
            }
            $node->[2] = pos $$str_ref;
        }

        ### look for the closing tag
        if ($$str_ref =~ m{ \G \s* $QR_COMMENTS (?: ; \s* $QR_COMMENTS)? ([+=~-]?) $self->{'_end_tag'} }gcxs) {
            if ($one_tag_only) {
                $self->throw('parse', "Invalid char \"$1\" found at end of block") if $1;
                $self->throw('parse', "Missing END directive", $state[-1], pos($$str_ref)) if @state > 0;
                return \@tree;
            }

            $post_chomp = $1 || $self->{'POST_CHOMP'};
            $post_chomp =~ y/-=~+/1230/ if $post_chomp;
            $continue = 0;
            $post_op  = 0;
            next;
        }

        ### semi-colon = end of statement - we will need to continue parsing this tag
        if ($$str_ref =~ m{ \G ; \s* $QR_COMMENTS }gcxo) {
            $post_op   = 0;

        ### we are flagged to start capturing the output of the next directive - set it up
        } elsif ($node->[6]) {
            $post_op = 0;
            $capture = $node;

        ### allow next directive to be post-operative (or not)
        } else {
            $post_op = $node;
        }

        ### no closing tag yet - no need to get an opening tag on next loop
        $self->throw('parse', "Not sure how to handle tag", $node, pos($$str_ref)) if $continue == pos $$str_ref;
        $continue = pos $$str_ref;
    }

    ### cleanup the tree
    unshift(@tree, @blocks) if @blocks;
    unshift(@tree, ['META', 1, 1, {@meta}]) if @meta;
    $self->throw('parse', "Missing END directive", $state[-1], pos($$str_ref)) if @state > 0;

    ### pull off the last text portion - if any
    if (pos($$str_ref) != length($$str_ref)) {
        my $text  = substr $$str_ref, pos($$str_ref);
        if (! $post_chomp) { }
        elsif ($post_chomp == 1) { $text =~ s{ ^ [^\S\n]* \n }{}x  }
        elsif ($post_chomp == 2) { $text =~ s{ ^ \s+         }{ }x }
        elsif ($post_chomp == 3) { $text =~ s{ ^ \s+         }{}x  }
        push @$pointer, $text if length $text;
    }

    return \@tree;
}

###----------------------------------------------------------------###

sub process {
    my ($self, $in, $swap, $out, @ARGS) = @_;
    delete $self->{'error'};

    if ($self->{'DEBUG'}) { # "enable" some types of tt style debugging
        $self->{'_debug_dirs'}  = 1 if $self->{'DEBUG'} =~ /^\d+$/ ? $self->{'DEBUG'} & 8 : $self->{'DEBUG'} =~ /dirs|all/;
        $self->{'_debug_undef'} = 1 if $self->{'DEBUG'} =~ /^\d+$/ ? $self->{'DEBUG'} & 2 : $self->{'DEBUG'} =~ /undef|all/;
    }

    my $args;
    $args = ($#ARGS == 0 && UNIVERSAL::isa($ARGS[0], 'HASH')) ? {%{$ARGS[0]}} : {@ARGS} if scalar @ARGS;

    ### get the content
    my $content;
    if (ref $in) {
        if (ref($in) eq 'SCALAR') { # reference to a string
            $content = $in;
        } elsif (UNIVERSAL::isa($in, 'CODE')) {
            $in = $in->();
            $content = \$in;
        } elsif (ref($in) eq 'HASH') { # pre-prepared document
            $content = $in;
        } else { # should be a file handle
            local $/ = undef;
            $in = <$in>;
            $content = \$in;
        }
    } else {
        ### should be a filename
        $content = $in;
    }


    ### prepare block localization
    my $blocks = $self->{'BLOCKS'} ||= {};


    ### do the swap
    my $output = '';
    eval {

        ### localize the stash
        $swap ||= {};
        my $var1 = $self->{'_vars'} ||= {};
        my $var2 = $self->{'STASH'} || $self->{'VARIABLES'} || $self->{'PRE_DEFINE'} || {};
        $var1->{'global'} ||= {}; # allow for the "global" namespace - that continues in between processing
        my $copy = {%$var2, %$var1, %$swap};

        local $self->{'BLOCKS'} = $blocks = {%$blocks}; # localize blocks - but save a copy to possibly restore
        local $self->{'_template'};

        delete $self->{'_debug_off'};
        delete $self->{'_debug_format'};

        ### handle pre process items that go before every document
        my $pre = '';
        if ($self->{'PRE_PROCESS'}) {
            _load_template_meta($self, $content);
            foreach my $name (@{ $self->split_paths($self->{'PRE_PROCESS'}) }) {
                $self->_process($name, $copy, \$pre);
            }
        }

        ### process the central file now - catching errors to allow for the ERROR config
        eval {
            local $self->{'STREAM'} = undef if $self->{'WRAPPER'};

            ### handle the PROCESS config - which loads another template in place of the real one
            if (exists $self->{'PROCESS'}) {
                _load_template_meta($self, $content);
                foreach my $name (@{ $self->split_paths($self->{'PROCESS'}) }) {
                    next if ! length $name;
                    $self->_process($name, $copy, \$output);
                }

                ### handle "normal" content
            } else {
                local $self->{'_start_top_level'} = 1;
                $self->_process($content, $copy, \$output);
            }
        };

        ### catch errors with ERROR config
        if (my $err = $@) {
            $err = $self->exception('undef', $err) if ! UNIVERSAL::can($err, 'type');
            die $err if $err->type =~ /stop|return/;
            my $catch = $self->{'ERRORS'} || $self->{'ERROR'} || die $err;
            $catch = {default => $catch} if ! ref $catch;
            my $type = $err->type;
            my $last_found;
            my $file;
            foreach my $name (keys %$catch) {
                my $_name = (! defined $name || lc($name) eq 'default') ? '' : $name;
                if ($type =~ / ^ \Q$_name\E \b /x
                    && (! defined($last_found) || length($last_found) < length($_name))) { # more specific wins
                    $last_found = $_name;
                    $file       = $catch->{$name};
                }
            }

            ### found error handler - try it out
            if (defined $file) {
                $output = '';
                local $copy->{'error'} = local $copy->{'e'} = $err;
                local $self->{'STREAM'} = undef if $self->{'WRAPPER'};
                $self->_process($file, $copy, \$output);
            }
        }

        ### handle wrapper directives
        if (exists $self->{'WRAPPER'}) {
            _load_template_meta($self, $content);
            foreach my $name (reverse @{ $self->split_paths($self->{'WRAPPER'}) }) {
                next if ! length $name;
                local $copy->{'content'} = $output;
                my $out = '';
                local $self->{'STREAM'} = undef;
                $self->_process($name, $copy, \$out);
                $output = $out;
            }
            if ($self->{'STREAM'}) {
                print $output;
                $output = 1;
            }
        }

        $output = $pre . $output if length $pre;

        ### handle post process items that go after every document
        if ($self->{'POST_PROCESS'}) {
            _load_template_meta($self, $content);
            foreach my $name (@{ $self->split_paths($self->{'POST_PROCESS'}) }) {
                $self->_process($name, $copy, \$output);
            }
        }

    };

    ### clear blocks as asked (AUTO_RESET) defaults to on
    $self->{'BLOCKS'} = $blocks if exists($self->{'AUTO_RESET'}) && ! $self->{'AUTO_RESET'};

    if (my $err = $@) {
        $err = $self->exception('undef', $err) if ! UNIVERSAL::can($err, 'type');
        if ($err->type !~ /stop|return|next|last|break/) {
            $self->{'error'} = $err;
            die $err if $self->{'RAISE_ERROR'};
            return;
        }
    }

    ### send the content back out
    $out ||= $self->{'OUTPUT'};
    if (ref $out) {
        if (UNIVERSAL::isa($out, 'CODE')) {
            $out->($output);
        } elsif (UNIVERSAL::can($out, 'print')) {
            $out->print($output);
        } elsif (UNIVERSAL::isa($out, 'SCALAR')) { # reference to a string
            $$out = $output;
        } elsif (UNIVERSAL::isa($out, 'ARRAY')) {
            push @$out, $output;
        } else { # should be a file handle
            print {$out} $output;
        }
    } elsif ($out) { # should be a filename
        my $file;
        if ($out =~ m|^/|) {
            if (! $self->{'ABSOLUTE'}) {
                $self->throw($self->{'error'} = $self->exception('file', "ABSOLUTE paths disabled"));
            } else {
                $file = $out;
            }
        } elsif ($out =~ m|^\.\.?/|) {
            if (! $self->{'RELATIVE'}) {
                $self->throw($self->{'error'} = $self->exception('file', "RELATIVE paths disabled"));
            } else {
                $file = $out;
            }
        } else {
            my $path = $self->{'OUTPUT_PATH'};
            $path = '.' if ! defined $path;
            if (! -d $path) {
                require File::Path;
                File::Path::mkpath($path);
            }
            $file = "$path/$out";
        }
        open(my $fh, '>', $file)
            || $self->throw($self->{'error'} = $self->exception('file', "$out couldn't be opened for writing: $!"));
        if (my $bm = $args->{'binmode'}) {
            if (+$bm == 1) { binmode $fh }
            else           { binmode $fh, $bm }
        } elsif ($self->{'ENCODING'}) {
            if (eval { require Encode } && defined &Encode::encode) {
                $output = Encode::encode($self->{'ENCODING'}, $output);
            }
        }
        print {$fh} $output;
    } else {
        print $output;
    }

    return if $self->{'error'};
    return 1;
}

sub _load_template_meta {
    my $self = shift;
    return if $self->{'_template'}; # only do once as need

    eval {
        ### load the meta data for the top document
        ### this is needed by some of the custom handlers such as PRE_PROCESS and POST_PROCESS
        my $content = shift;
        my $doc     = $self->{'_template'} = ref($content) eq 'HASH' ? $content : $self->load_template($content) || {};
        my $meta    = $doc->{'_perl'} ? $doc->{'_perl'}->{'meta'}
            : ($doc->{'_tree'} && ref($doc->{'_tree'}->[0]) && $doc->{'_tree'}->[0]->[0] eq 'META') ? $doc->{'_tree'}->[0]->[3]
            : {};

        $self->{'_template'} = $doc;
        @{ $doc }{keys %$meta} = values %$meta;
    };

    return;
}

###----------------------------------------------------------------###

1;

__END__

=head1 DESCRIPTION

The Template::Alloy::TT role provides the syntax and the interface for
Template::Toolkit version 1, 2, and 3.  It also brings many of the
features from the various templating systems.

And it is fast.

See the Template::Alloy documentation for configuration and other
parameters.

=head1 HOW IS Template::Alloy DIFFERENT FROM Template::Toolkit

Alloy uses the same base template syntax and configuration items as
TT2, but the internals of Alloy were written from scratch.
Additionally much of the planned TT3 syntax is supported as well as
most of that of HTML::Template::Expr.  The following is a list of some
of the ways that the configuration and syntax of Alloy are different
from that of TT2.  Note: items that are planned to work in TT3 are
marked with (TT3).

=over 4

=item

Numerical hash keys work

    [% a = {1 => 2} %]

=item

Quoted hash key interpolation is fine

    [% a = {"$foo" => 1} %]

=item

Multiple ranges in same constructor

    [% a = [1..10, 21..30] %]

=item

Constructor types can call virtual methods. (TT3)

    [% a = [1..10].reverse %]

    [% "$foo".length %]

    [% 123.length %]   # = 3

    [% 123.4.length %]  # = 5

    [% -123.4.length %] # = -5 ("." binds more tightly than "-")

    [% (a ~ b).length %]

    [% "hi".repeat(3) %] # = hihihi

    [% {a => b}.size %] # = 1

=item

The "${" and "}" variable interpolators can contain expressions,
not just variables.

    [% [0..10].${ 1 + 2 } %] # = 4

    [% {ab => 'AB'}.${ 'a' ~ 'b' } %] # = AB

    [% color = qw/Red Blue/; FOR [1..4] ; color.${ loop.index % color.size } ; END %]
      # = RedBlueRedBlue

=item

You can use regular expression quoting.

    [% "foo".match( /(F\w+)/i ).0 %] # = foo

=item

Tags can be nested.

    [% f = "[% (1 + 2) %]" %][% f|eval %] # = 3

=item

Arrays can be accessed with non-integer numbers.

    [% [0..10].${ 2.3 } %] # = 3

=item

Reserved names are less reserved. (TT3)

    [% GET GET %] # gets the variable named "GET"

    [% GET $GET %] # gets the variable who's name is stored in "GET"

=item

Filters and SCALAR_OPS are interchangeable. (TT3)

    [% a | length %]

    [% b . lower %]

=item

Pipe "|" can be used anywhere dot "." can be and means to call
the virtual method. (TT3)

    [% a = {size => "foo"} %][% a.size %] # = foo

    [% a = {size => "foo"} %][% a|size %] # = 1 (size of hash)

=item

Pipe "|" and "." can be mixed. (TT3)

    [% "aa" | repeat(2) . length %] # = 4

=item

Added V2PIPE configuration item

Restores the behavior of the pipe operator to be
compatible with TT2.

With V2PIPE = 1

    [% PROCESS a | repeat(2) %] # = value of block or file a repeated twice

With V2PIPE = 0 (default)

    [% PROCESS a | repeat(2) %] # = process block or file named a ~ a

=item

Added V2EQUALS configuration item

Allows for turning off TT2 "==" behavior.  Defaults to 1
in TT syntaxes and to 0 in HT syntaxes.

    [% CONFIG V2EQUALS => 1 %][% ('7' == '7.0') || 0 %]
    [% CONFIG V2EQUALS => 0 %][% ('7' == '7.0') || 0 %]

Prints

    0
    1

=item

Added AUTO_EVAL configuration item.

Default false.  If true, will automatically call eval filter
on double quoted strings.

=item

Added SHOW_UNDEFINED_INTERP configuration item.

Default false.  If true, will leave in place interpolated
values that weren't defined.  You can then use the
Velocity notation $!foo to not show these values.

=item

Added Virtual Object Namespaces. (TT3)

The Text, List, and Hash types give direct access
to virtual methods.

    [% a = "foobar" %][% Text.length(a) %] # = 6

    [% a = [1 .. 10] %][% List.size(a) %] # = 10

    [% a = {a=>"A", b=>"B"} ; Hash.size(a) %] = 2

    [% foo = {a => 1, b => 2}
       | Hash.keys
       | List.join(", ") %] # = a, b

=item

Added "fmt" scalar, list, and hash virtual methods.

    [% list.fmt("%s", ", ") %]

    [% hash.fmt("%s => %s", "\n") %]

=item

Added missing HTML::Template::Expr vmethods

The following vmethods were added - they correspond to the
perl functions of the same name.

    abs
    atan2
    cos
    exp
    hex
    lc
    log
    oct
    sin
    sprintf
    sqrt
    srand
    uc

=item

Allow all Scalar vmethods to behave as top level functions.

    [% sprintf("%d %d", 7, 8) %] # = "7 8"

The following are equivalent in Alloy:

    [% "abc".length %]
    [% length("abc") %]

This feature may be disabling by setting the
VMETHOD_FUNCTIONS configuration item to 0.

This is similar to how HTML::Template::Expr operates, but
now you can use this functionality in TT templates as well.

=item

Whitespace is less meaningful. (TT3)

    [% 2-1 %] # = 1 (fails in TT2)

=item

Added pow operator.

    [% 2 ** 3 %] [% 2 pow 3 %] # = 8 8

=item

Added string comparison operators (gt ge lt le cmp)

    [% IF "a" lt "b" %]a is less[% END %]

=item

Added numeric comparison operator (<=>)

This can be used to make up for the fact that TT2 made == the
same as eq (which will hopefully change - use eq when you mean eq).

    [% IF ! (a <=> b) %]a == b[% END %]

    [% IF (a <=> b) %]a != b[% END %]

=item

Added self modifiers (+=, -=, *=, /=, %=, **=, ~=). (TT3)

    [% a = 2;  a *= 3  ; a %] # = 6
    [% a = 2; (a *= 3) ; a %] # = 66

=item

Added pre and post increment and decrement (++ --). (TT3)

    [% ++a ; ++a %] # = 12
    [% a-- ; a-- %] # = 0-1

=item

Added qw// contructor. (TT3)

    [% a = qw(a b c); a.1 %] # = b

    [% qw/a b c/.2 %] # = c

=item

Added regex contructor. (TT3)

    [% "FOO".match(/(foo)/i).0 %] # = FOO

    [% a = /(foo)/i; "FOO".match(a).0 %] # = FOO

=item

Allow for scientific notation. (TT3)

    [% a = 1.2e-20 %]

    [% 123.fmt('%.3e') %] # = 1.230e+02

=item

Allow for hexidecimal input. (TT3)

    [% a = 0xff0000 %][% a %] # = 16711680

    [% a = 0xff2 / 0xd; a.fmt('%x') %] # = 13a

=item

FOREACH variables can be nested.

    [% FOREACH f.b = [1..10] ; f.b ; END %]

Note that nested variables are subject to scoping issues.
f.b will not be reset to its value before the FOREACH.

=item

Post operative directives can be nested. (TT3)

Andy Wardley calls this side-by-side effect notation.

    [% one IF two IF three %]

    same as

    [% IF three %][% IF two %][% one %][% END %][% END %]


    [% a = [[1..3], [5..7]] %][% i FOREACH i = j FOREACH j = a %] # = 123567

=item

Semi-colons on directives in the same tag are optional. (TT3)

    [% SET a = 1
       GET a
     %]

    [% FOREACH i = [1 .. 10]
         i
       END %]

Note: a semi-colon is still required in front of any block directive
that can be used as a post-operative directive.

    [% 1 IF 0
       2 %]   # prints 2

    [% 1; IF 0
       2
       END %] # prints 1

Note2: This behavior can be disabled by setting the SEMICOLONS
configuration item to a true value.  If SEMICOLONS is true, then
a SEMICOLON must be set after any directive that isn't followed
by a post-operative directive.

=item

CATCH blocks can be empty.

TT2 requires them to contain something.

=item

Added a DUMP directive.

Used for Data::Dumpering the passed variable or expression.

   [% DUMP a.a %]

=item

Added CONFIG directive.

   [% CONFIG
        ANYCASE   => 1
        PRE_CHOMP => '-'
   %]

=item

Configuration options can use lowercase names instead
of the all uppercase names that TT2 uses.

    my $t = Template::Alloy->new({
        anycase     => 1,
        interpolate => 1,
    });

=item

Added LOOP directive (works the same as LOOP in HTML::Template.

   [%- var = [{key => 'a'}, {key => 'b'}] %]
   [%- LOOP var %]
     ([% key %])
   [%- END %]

   Prints

     (a)
     (b)

=item

Alloy can parse HTML::Template and HTML::Template::Expr documents
as well as TT2 and TT3 documents.

=item

Added SYNTAX configuration.  The SYNTAX configuration can be
used to change what template syntax will be used for parsing
included templates or eval'ed strings.

   [% CONFIG SYNTAX => 'hte' %]
   [% var = '<TMPL_VAR EXPR="sprintf('%s', 'hello world')">' %]
   [% var | eval %]

=item

Added @() and $() and CALL_CONTEXT.  Template::Toolkit uses a
\concept that Alloy refers to as "smart" context.  All function
calls or method calls of variables in Template::Toolkit are made
in list context.  If one item is in the list, it is returned.  If
two or more items are returned - it returns an arrayref.  This
"does the right thing" most of the time - but can cause confusion
in some cases and is difficult to work around without writing
wrappers for the functions or methods in Perl.

Alloy has introduced the CALL_CONTEXT configuration item which
defaults to "smart," but can also be set to "list" or "item."
List context will always return an arrayref from called functions
and methods and will call in list context.  Item context will
always call in item (scalar) context and will return one item.

The @() and $() operators allow for functions embedded inside
to use list and item context (respectively).  They are modelled
after the corresponding Perl 6 context specifiers.  See the
Template::Alloy::Operators perldoc and CALL_CONTEXT configuration
documentation for more information.

    [% array = @( this.get_rows ) %]

    [% item  = $( this.get_something ) %]

=item

Added -E<gt>() MACRO operator.

The -E<gt>() operator behaves similarly to the MACRO directive,
but can be used to pass functions to map, grep, and sort vmethods.

    [% MACRO foo(n) BLOCK %]Say [% n %][% END %]
    [% foo = ->(n){ "Say $n" } %]

    [% [0..10].grep(->(this % 2)).join %] prints 3 5 7 9
    [% ['a' .. 'c'].map(->(a){ a.upper }).join %] prints A B C
    [% [1,2,3].sort(->(a,b){ b <=> a }).join %] prints 3 2 1

=item

The RETURN directive can take a variable or expression as a return
value.  Their are also "return" list, item, and hash vmethods.  Return
will also return from an enclosing MACRO.

    [% a = ->(n){ [1..n].return } %]

=item

Alloy does not generate Perl code.

It generates an "opcode" tree.  The opcode tree is an arrayref
of scalars and array refs nested as deeply as possible.  This "simple"
structure could be shared TT implementations in other languages
via JSON or YAML.  You can optionally enable generating Perl code by
setting COMPILE_PERL = 1.

=item

Alloy uses storable for its compiled templates.

If EVAL_PERL is off, Alloy will not eval_string on ANY piece of information.

=item

There is eval_filter and MACRO recursion protection

You can control the nested nature of eval_filter and MACRO
recursion using the MAX_EVAL_RECURSE and MAX_MACRO_RECURSE
configuration items.

=item

There is no context.

Alloy provides a context object that mimics the Template::Context
interface for use by some TT filters, eval perl blocks, views,
and plugins.

=item

There is no provider.

Alloy uses the load_template method to get and cache templates.

=item

There is no parser/grammar.

Alloy has its own built-in recursive regex based parser and grammar system.

Alloy can actually be substituted in place of the native Template::Parser and
Template::Grammar in TT by using the Template::Parser::Alloy module.  This
module uses the output of parse_tree to generate a TT style compiled perl
document.

=item

The DEBUG directive is more limited.

It only understands DEBUG_DIRS (8) and DEBUG_UNDEF (2).

=item

Alloy has better line information

When debug dirs is on, directives on different lines separated
by colons show the line they are on rather than a general line range.

Parse errors actually know what line and character they occured at.

=back

=head1 UNSUPPORTED TT2 CONFIGURATION

=over 4

=item LOAD_TEMPLATES

Template::Alloy has its own mechanism for loading and storing compiled
templates.  TT would use a Template::Provider that would return a
Template::Document.  The closest thing in Template::Alloy is the
load_template method.  There is no immediate plan to support the TT
behavior.

=item LOAD_PLUGINS

Template::Alloy uses its own mechanism for loading plugins.  TT would
use a Template::Plugins object to load plugins requested via the USE
directive.  The functionality for doing this in Template::Alloy is
contained in the list_plugins method and the play_USE method.  There
is no immediate plan to support the TT behavior.

Full support is offered for the PLUGINS and LOAD_PERL configuration
items.

Also note that Template::Alloy only natively supports the Iterator
plugin.  Any of the other plugins requested will need to provided by
installing Template::Toolkit or the appropriate plugin module.

=item LOAD_FILTERS

Template::Alloy uses its own mechanism for loading filters.  TT would
use the Template::Filters object to load filters requested via the
FILTER directive.  The functionality for doing this in Template::Alloy
is contained in the list_filters method and the play_expr method.

Full support is offered for the FILTERS configuration item.

=item TOLERANT

This option is used by the LOAD_TEMPLATES and LOAD_PLUGINS options and
is not applicable in Template::Alloy.

=item SERVICE

Template::Alloy has no concept of service (theoretically the
Template::Alloy is the "service").

=item CONTEXT

Template::Alloy provides its own pseudo context object to plugins,
filters, and perl blocks.  The Template::Alloy model doesn't really
allow for a separate context.  Template::Alloy IS the context.

=item PARSER

Template::Alloy has its own built in parser.  The closest similarity
is the parse_tree method.  The output of parse_tree is an optree that
is later run by execute_tree.  Alloy provides a backend to the
Template::Parser::Alloy module which can be used to replace the
default parser when using the standard Template::Toolkit library.

=item GRAMMAR

Template::Alloy maintains its own grammar.  The grammar is defined
in the parse_tree method and the callbacks listed in the global
$Template::Alloy::Parse::DIRECTIVES hashref.

=back

=head1 AUTHOR

Paul Seamons <perl at seamons dot com>

=head1 LICENSE

This module may be distributed under the same terms as Perl itself.

=cut
