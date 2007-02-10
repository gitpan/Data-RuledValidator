package Data::RuledValidator;

our $VERSION = '0.06';

use strict;
use warnings "all";
use File::Slurp;
use Data::RuledValidator::Util;
use Data::RuledValidator::Filter;
use Class::Inspector;
use UNIVERSAL::require;
use List::MoreUtils qw/any uniq/;
use Module::Pluggable search_path => [qw/Data::RuledValidator::Plugin/];

use overload 
  '""'  => \&valid,
  '@{}' => \&_result;

my %RULES;
my %COND_OP;
my %MK_CLOSURE;
my %REQUIRED;
my %FILTER;

sub _rules{
  my($self, $rule) = @_;
  if(@_ == 2){
    if(exists $RULES{$rule}){
      my $t = (stat $rule)[9];
      $RULES{$rule}->{time} ||= $t;
      if($RULES{$rule}->{time} < $t){
        delete $RULES{$rule}->{coded_rule};
        delete $REQUIRED{$rule};
        $RULES{$rule}->{time} = $t;
      }
    }
    return $RULES{$rule}->{coded_rule} ||= {};
  }else{
    return \%RULES;
  }
}

sub id_key{
  my($self, $rule, $id_key) = @_;
  @_ == 3 ? $RULES{$rule}->{id_key} = $id_key: $RULES{$rule}->{id_key};
};

sub id_method{
  my($self, $rule, $id_method) = @_;
  $rule ||= $self->rule or Carp::croak("first argument 'rule' is missing;");
  @_ == 3 ? $RULES{$rule}->{id_method} = $id_method: $RULES{$rule}->{id_method} || $self->{id_method};
};

sub _regex_group{
  my($self, $rule, $id_name) = @_;
  if(@_ == 3){
    return push @{$RULES{$rule}->{_regex_group} ||= []}, $id_name;
  }else{
    return @{$RULES{$rule}->{_regex_group} || []}
  }
};

sub import{
  my($class, %option) = @_;
  my %import;
  $option{import} = ref $option{import} ?   $option{import}   :
                        $option{import} ? [ $option{import} ] :
                                          []                  ;
  @import{ map { __PACKAGE__ . '::Plugin::' . $_ }  @{$option{import}}} = ();
  foreach my $plugin (__PACKAGE__->plugins){
    unless(Class::Inspector->loaded($plugin)){
      if( (not @{$option{import}} or exists $import{$plugin} ) ){
        $plugin->require
      }
      delete $import{ $plugin };
      if($@ and my $er = $option{import_error}){
        if($er == 1){
          warn "Plugin import Error: $plugin - $@";
        }else{
          die  "Plugin import Error: $plugin - $@";
        }
      }
    }else{
      delete $import{ $plugin };
    }
  }
  unless(Class::Inspector->loaded(__PACKAGE__ . '::Plugin::Core')){
    (__PACKAGE__ . '::Plugin::Core')->require;
  }
  if(@{$option{import}} and %import){
    die join(", ", keys %import) . " plugins doesn't exist.";
  }

}

sub _cond_op{ my $self = shift; return @_ ? $COND_OP{shift()} : keys %COND_OP};

sub add_operator{
  my($self, %op_sub) = @_;
  while(my($op, $sub) = each %op_sub){
    if($MK_CLOSURE{$op}){
      Carp::croak("$op has already defined as normal operator.");
    }
    $MK_CLOSURE{$op} = $sub;
  }
}

sub add_condition_operator{
  my($self, %op_sub) = @_;
  while(my($op, $sub) = each %op_sub){
    if(defined $COND_OP{$op}){
      Carp::croak("$op is already defined as condition operator.");
    }
    $COND_OP{$op} = $sub;
  }
}

sub create_alias_operator{
  my($self, $alias, $original) = @_;
  if($MK_CLOSURE{$alias}){
    Carp::croak("$alias has already defined as context/normal operator.");
  }elsif(not $MK_CLOSURE{$original}){
    Carp::croak("$original is not defined as context/normal operator.");
  }
  $MK_CLOSURE{$alias} = $MK_CLOSURE{$original};
}

sub create_alias_cond_operator{
  my($self, $alias, $original) = @_;
  if($COND_OP{$alias}++){
    Carp::croak("$alias has already defined as condition operator.");
  }
  $COND_OP{$alias} = $COND_OP{$original};
}

sub new{
  my($class, %option) = @_;
  $option{result}   = {};
  $option{valid}    = 0;
  $option{rule}   ||= '';
  $option{filter_replace} ||= 0;
  my $o = bless \%option, $class;
  return $o;
}

sub rule{
  my($self, $rule) = @_;
  if(@_ == 2){
    return $self->{rule} = $rule;
  }else{
    return $self->{rule};
  }
}

sub list_plugins{
  my($self) = @_;
  return $self->plugins;
}

sub obj{ shift()->{obj} };

sub id_obj{ shift()->{id_obj} };

sub to_obj{ shift()->{to_obj} };

sub method{ shift()->{method} };

sub required_alias_name{
  my($self, $name) = @_;
  if(@_ == 2){
    return $self->{required_alias_name} = $name;
  }else{
    return $self->{required_alias_name} || 'required';
  }
}

sub _parse_definition{
  my($self, $defs) = @_;
  my @def;
  my %required;
  my %filter;
  my $required_name = $self->required_alias_name;
  foreach my $def (@$defs){
    my $alias = $def =~ s/^\s*(\w+)\s*=\s*// ? $1 : '';
    if($alias and $alias eq $required_name){
      @required{split /\s*,\s*/, $def} = ();
    }elsif($def =~/filter\s+(.+)\s+with\s+(.+)\s*$/){
      my($keys, $values) = ($1, $2);
      @filter{split /\s*,\s*/, $keys} = [ split /\s*,\s*/, $values ];
    }else{
      my $filter;
      if($def =~ s/\s*with\s*(.+?)$//){
        $filter = [ split /\s*,\s*/, $filter = $1];
      }
      my($key, $op, $cond) = split /\s+/, $def, 3;
      my($closure, $flg) = $MK_CLOSURE{$op} ? $MK_CLOSURE{$op}->($key, $cond, $op) : Carp::croak("not defined operator: $op");
      $flg ||= 0;
      if($flg & NEED_ALIAS and not $alias){
        Carp::croak("Rule Syntax Error: $op needs alias name.");
      }
      push @def, [$alias, $key, $op, $closure, $flg, $filter];
    }
  }
  return(\@def, \%required, \%filter);
}

sub by_sentence{
  my $given_data = {};
  $given_data = pop(@_)  if ref $_[-1] eq 'HASH';

  my($self, @definition) = @_;
  @definition = @{$definition[0]} if ref $definition[0] eq 'ARRAY';
  my($defs, $required, $filter) = $self->_parse_definition(\@definition);
  return $self->_validator($defs, $given_data, $required, $filter);
}

sub _get_value{
  my($self, $last_obj, $method, $key) = @_;
  my @method =  ref $method ? @$method : $method;
  $last_obj = $last_obj->$_ foreach (@method[0 .. ($#method - 1)]);
  my $m = $method[$#method];
  return $last_obj->$m($key);
}

sub _validator{
  my($self, $defs, $given_data, $required, $filter) = @_;
  my($obj, $method) = ($self->obj, $self->method);
  my(%result, %failure, @missing);
  my $all_result = 1;
  my $required_valid = $self->required_alias_name . '_valid';
  $result{$required_valid} = 1 if %$required;
  $self->result(\%result);

  foreach my $def (@$defs){
    my($alias, $key, $op, $sub, $flg, $here_filter) = @$def;
    my $result = undef;
    Carp::craok('cannot define same combination of key/alias and operator twice.') if exists $result{$alias . '_' . $op};
    $alias ||= $key;
    my @value = $self->_get_value($obj, $method, $key);
    if(my $key_filter = $filter->{$key}){
      $self->_filter_value($key, \@value, $key_filter);
      $self->_filtered_value($key, \@value);
    }
    if(ref $here_filter eq 'ARRAY'){
      $self->_filter_value($key, \@value, $here_filter);
    }
    if(defined $MK_CLOSURE{$op}){
      if($flg & IGNORE_REQUIRED or any sub{defined $_}, @value){
        $result = $sub->($self, \@value, $alias, $obj, $method, $given_data) || 0;
        $result{ $alias . '_' . $op } = $result;
        $result{ $alias . '_valid'  } ||= 1;
        $result{ $alias . '_valid'  }  &= $result;
        if(not $result and @value and not defined $failure{$alias . '_' . $op}){
          $failure{$alias . '_' . $op} = \@value;
        }
        $all_result &= $result;
      }else{
        if(exists $required->{$alias}){
          $result{$required_valid} &= $result || 0;
        }
        push @missing, $alias;
      }
    }
  }

  $self->valid($all_result);
  $self->missing(\@missing);
  $self->result(\%result);
  $self->failure(\%failure);
  $self->_do_filter_replace;
  return $self;
}

sub filter_replace{
  my($self, $value) = @_;
  return $self->{filter_replace} = $value if @_ == 2;
  return $self->{filter_replace};
}

sub _do_filter_replace{
  my($self) = @_;
  return unless my $filter = $self->filter_replace;

  my %filter_replace = %{$self->{filtered_value} || {}};
  my($obj, $method) = ($self->obj, $self->method);
  if(ref $filter){
    while(my($k, $v) = each %filter_replace){
      $obj->$method($k, $v);
    }
  }else{
    while(my($k, $v) = each %filter_replace){
      $obj->$method($k, @$v);
    }
  }
}

sub _filtered_value{
  my($self, $key, $value) = @_;
  return $self->{filtered_value}->{$key} = $value if @_ == 3;
  return $self->{filtered_value}->{$key};
}

sub _filter_value{
  my($self, $key, $value, $key_filter) = @_;
  foreach my $value (@$value){
    foreach my $filter (@$key_filter){
      Data::RuledValidator::Filter->$filter(\$value);
    }
  }
}

sub result{
  my($self, $result) = @_;
  $self->{result} = $result  if @_ == 2;
  return($self->{result} ||= {});
}

sub failure{
  my($self, $failure) = @_;
  $self->{failure} = $failure  if @_ == 2;
  return($self->{failure} || {});
}

sub _result{
  my($self) = @_;
  return [%{$self->{result}}];
}

sub missing{
  my($self, $missing) = @_;
  if(@_ == 2){
    $self->{missing} = [ uniq @$missing ];
  }
  return $self->{missing};
}

sub valid{
  my($self, $valid) = @_;
  if(defined $valid){
    $self->{valid} = $valid;
  }
  if(exists $self->{valid}){
    my $required_valid = $self->required_alias_name . '_valid';
    my $not_fail = exists $self->{failure} ? not %{$self->failure} : 1;
    if(exists $self->{result}->{$required_valid}){
      return $self->ok($required_valid) ? $not_fail : 0;
    }else{
      return $not_fail;
    }
  }else{
    return;
  }
}

sub reset{
  my($self) = @_;
  delete $self->{$_} foreach qw/result valid failure/; # wrong right/; future
}

sub by_rule{
  my $given_data = {};
  $given_data = pop(@_)  if ref $_[-1] eq 'HASH';
  my($self, $rule) = @_;

  $rule = $rule ? $self->rule($rule) : $self->rule;
  Carp::croak("need rule name")  unless $rule;
  $self->_parse_rule($rule) unless %{ $self->_rules($rule) || {} };
  my($obj, $method) = ($self->id_obj || $self->obj, $self->id_method($rule) || $self->method);
  my $id_key = $self->id_key($rule);
  my $rule_name = $id_key =~ /^ENV_(.+)$/i ? $ENV{uc($1)} : $self->_get_value($obj, $method, $id_key || ());

  my $defs = defined $rule_name ? $self->_rules($rule)->{$rule_name} : undef;
  unless($defs){
    foreach my $r ($self->_regex_group($rule)){
      last if $defs = $self->_rules($rule)->{$r};
    }
  }
  $self->{rule_name} = $rule_name;
  return $self->_validator($defs || [], $given_data, $REQUIRED{$rule_name}, $FILTER{$rule_name});
}

sub _distinct_rule{
  my($self, $global_rule, $rule) = @_;
  my %has;
  my %na;
  my @new_rule;
  my @rule;
  my $first_rule_line = $rule->[0];
  if(    ref $first_rule_line  eq 'ARRAY'
     and $first_rule_line->[1] eq 'GLOBAL'
     and $first_rule_line->[2] eq 'is'
     and $first_rule_line->[3] eq 'n/a'
  ){
    @rule = @$rule;
  }else{
    @rule = (@$global_rule, @$rule);
  }
  foreach my $def (reverse @rule){
    next unless $def->[2];
    my($alias, $key, $op, $cond) = @$def;
    if(exists $MK_CLOSURE{$op}){
      my $alias = $alias || $key;
      $na{$alias}->{$op} = 1 if $cond eq 'n/a';
      push @new_rule, $def unless $na{$alias}->{$op} or $has{$alias}->{$op}++;
    }else{
      push @new_rule, $def;
    }
  }
  return [reverse @new_rule];
}

sub _parse_rule{
  my($self, $rule) = @_;
  my $rules = $self->_rules($rule);
  my $id_name = 'GLOBAL';
  my @rule;
  if(ref $rule eq 'SCALAR'){
    @rule = split/[\n\r]/, $$rule;
  }else{
    @rule = File::Slurp::read_file($rule)
        or Carp::croak "cannot open $rule";
  }
  foreach(@rule){
    chomp;
    my $line = $_;
    $line =~s/^\s+//;
    $line =~s/\s+$//;
    next unless $line and $line !~ /^\s*#/;
    my $is_regex = 0;
    if($line =~ s/^;+path;+/;/ or $line =~ s/path\{/\{/){
      $is_regex = 1;
      $line =~ s{/+$}{};
      $line = '^'. $line . '/?$';
    }elsif($line =~ s/^;+r;+/;/ or $line =~ s/r\{/\{/){
      $is_regex = 1;
    }
    if($line =~s/^ID_KEY\s+//i){
      $self->id_key($rule, $line);
    }elsif($line =~s/^ID_METHOD\s+//i){
      my @method = split /\s+/, $line;
      $self->id_method($rule, [grep $_, @method]);
    }elsif($line =~/^\s*\{\s*([^\s]+)\s*\}\s*$/ or $line =~m|^\s*;+\s*([^\s]+)\s*$|){
      # page name
      $id_name = $1;
      $rules->{$id_name} ||= [];
      $self->_regex_group($rule, $id_name) if $is_regex;
    }else{
      # rule
      push @{$rules->{$id_name}}, $line;
    }
  }
  my($global_rule, $required, $filter) = $self->_parse_definition($rules->{GLOBAL});
  $rules->{  GLOBAL } = $global_rule ||= [];
  $REQUIRED{ GLOBAL } = $required;
  $FILTER{   GLOBAL } = $filter;
  while(my($id_name, $defs) = each %$rules){
    next if $id_name eq 'GLOBAL';
    my($rule, $required, $filter) = $self->_parse_definition($defs);
    $rules->{  $id_name } = $self->_distinct_rule($global_rule, $rule ||= []);
    $REQUIRED{ $id_name } = %$required ? $required : $REQUIRED{ GLOBAL };
    $FILTER{   $id_name } = %$filter   ? $filter   : $FILTER{ GLOBAL   };
  }
}

sub ok{ return shift()->{result}->{shift()}}

sub valid_ok{ return shift()->{result}->{shift() . '_valid'}}

use Data::RuledValidator::Closure;

1;

=head1 NAME

Data::RuledValidator - data validator with rule

=head1 DESCRIPTION

Data::RuledValidator is validator of data.
This needs rule which is readable by not programmer ... so it is like specification.

=head1 WHAT FOR ?

One programmer said;

 specification is in code, so documentation is not needed.

Another programmers said;

 code is specification, so if I write specification, it is against DRY.

It is excuse of them. They may dislike to write documents, they may be not good at writing documents,
and/or they may think validation check is trivial task.
But, if specification is used by programming and we needn't write program,
they will start to write specification. And, at last, we need specification.

=head1 SYNOPSIS

You can use this without rule file.

 BEGIN{
   $ENV{REQUEST_METHOD} = "GET";
   $ENV{QUERY_STRING} = "page=index&i=9&k=aaaaa&v=bbbb";
 }
 
 use Data::RuledValidator;

 use CGI;
 
 my $v = Data::RuledValidator->new(obj => CGI->new, method => "param");
 print $v->by_sentence("i is num", "k is word", "v is word", "all of i,v,k");  # return 1 if valid

This means that parameter of CGI object, i is number, k is word,
v is also word and needs all of i, k and v.

Next example is using following rule in file "validator.rule";

 ;;GLOBAL
 
 ID_KEY  page
 
 i is number
 k is word
 v is word
 
 ;;index
 all of i, k, v

And code is(environmental values are as same as first example):

 my $v = Data::RuledValidator->new(obj => CGI->new, method => "param", rule => "validator.rule");
 print $v->by_rule; # return 1 if valid

This is as nearly same as first example.
left value of ID_KEY, "page" is parameter name to specify rule name to use.

 my $q = CGI->new;
 $id = $q->param("page");

Now, $id is "index" (see above environmental values in BEGIN block),
use rule in "index". The specified module and method in new is used.
"index" rule is following:

 ;;index
 all of i, k, v

Global rule is applied as well.

 i is number
 k is word
 v is word

So it is as same as first example.
This means that parameter of CGI object, i is number, k is word,
v is also word and needs all of i, k and v.

=head1 RuledValidator GENERAL IDEA

=over 4

=item * Object

Object has data which you want to check
and Object has Method which returns Value(s) from Object's data.

=item * Key

Basicaly, Key is the key which is passed to Object Method.

=item * Value(s)

Value(s) are the returned of the Object Mehotd passed Key.

=item * Operator

Operator is operator to check Value(s).

=item * Condition

Condition is the condition for Operator
to judge whether Value(s) is/are valid or not.

=back

=head1 USING OPTION

When using Data::RuledValidator, you can use option.

=over 4

=item import_error

This defines behavior when plugin is not imported correctly.

 use Data::RuledValidator import_error => 0;

If value is 0, do nothing. It is default.

 use Data::RuledValidator import_error => 1;

If value is 1, warn.

 use Data::RuledValidator import_error => 2;

If value is 2, die.

=item import

You can specify which plugins you want to load.

 use Data::RuledValdiator import => [qw/Email/];

If you don't specify any plugins, all plugins will be loaded.

=back

=head1 CONSTRUCTOR

=over 4

=item new

 my $v = Data::RuledValidator->new(
                obj    => $obj,
                method => $method,
                rule   => $rule_file_location,
          );

$obj is Object which has values which you want to check.
$method is Method of $obj which returns Value(s) which you want to check.
$rule_file_location is file location of rule file.

 my $v = Data::RuledValidator->new(obj => $obj, method => $method);

If you use "by_sentence" and/or you use "by_rule" with argument, no need to specify rule here.

You can use array ref for method. for example, $c is object, and $c->res->param is the way to get values.
pass [qw/res param/] to method.

If you need another object and/or method for identify to group name.

 my $v = Data::RuledValidator->new(obj => $obj, method => $method, id_obj => $id_obj, id_method => $id_method);

for validation, $obj->$method is used.
for identifying to group name, $id_obj->$id_method is used (when you omit id_method, method is used).

=back

=head2 CONSTRUCTOR OPTION

=over 4

=item rule

 rule => rule_file_location

explained above.

=item filter_replace

Data::RuledValidator has filter feature.
You can decide replace object method value with filtered value or not.

This option can take 3 kind of value.

 filter_replace => 0

This will not use filtered value.

 filter_replace => 1
 filter_replace => []

Use filtered value.
Using 1 or [] is depends on the way to set value with object method.

 1  ...  $q->param(key, @value);
 [] ...  $q->param(key, [ @value ]);

=back

=head1 METHOD for VALIDATION

=over 4

=item by_sentence

 $v->by_sentence("i is number", "k is word", ...);

The arguments is rule. You can write multiple sentence.
It returns $v object.

=item by_rule

 $v->by_rule();
 $v->by_rule($rule);

If $rule is omitted, using the file which is specified in new.
It returns $v object.

=item result

 $v->result;

The result of validation check.
This returned the following structure.

 {
   'i_is'    => 0,
   'v_is'    => 0,
   'z_match' => 1,
 }

This means

 key 'i' is invalid.
 key 'v' is invalid.
 key 'z' is valid.

You can get this result as following:

 %result = @$v;

=item valid

 $v->valid;

The result of total validation check.
The returned value is 1 or 0.

You can get this result as following, too:

 $result = $v;

=item failure

 $v->failure;

Given values to validation check.
Some/All of them are wrong value.
This returned, for example, the following structure.

 {
   'i_is'    => ['x', 'y', 'z'],
   'v_is'    => ['x@x.jp'],
   'z_match' => [0123, 1234],
 }

If you want wrong value only, use wrong method.

=item missing

The values included in rule is not given from object.
You can get such keys/aliases as following

 my $missing_arrayref = $v->missing;

$missing_arrayref likes as following;

 ['key', 'alias']

=item wrong

This is not implemented.

 $v->wrong;

It returns only wrong value.

 {
   'i_is'    => ['x', 'y', 'z'],
   'v_is'    => ['x@x.jp'],
   'z_match' => [0123, 1234],
 }

All of them are wrong values.

=item reset

 $v->reset();

The result of validation check is reseted.

=back

=head1 OTHER METHOD

=over 4

=item required_alias_name

 $v->required_alias_name

It is special alias name to specify required keys.

=item list_plugins

 $v->list_plugins;

list all plugins.

=item filter_replace

 $v->filter_replace;

This get/set new's option.
get/set value is 0, 1 or {}.

=back

=head1 RULE SYNTAX

Rule Syntax is very simple.

=over 4

=item ID_KEY Key

The right value is key which is passed to Object->Method.
The returned value of Object->Method(Key) is used to identify GROUP_NAME

 ID_KEY page

=item ID_METHOD method method ...

Note that: It is used, only when you need another method to identify to GROUP_NAME.

The right value is method which is used when Object->Method.
The returned value of Object->Method(Key)/Object->Method (Key is omitted)
is used to identify GROUP_NAME.

 ID_METHOD request action

This can be defined in constructor, new.

=item ;GROUP_NAME

start from ; is start of group and the end of this group is the line before next ';'.
If the value of Object->Method(ID_KEY) is equal GROUP_NAME, this group validation rule is used.

 ;index

You can write as following.

 {index}
 ;;;;index

You can repeat ';' any times.

=item ;r;^GROUP_NAME$

This is start of group, too.
If the value of Object->Method(ID_KEY) is match regexp ^GROUP_NAME$, this group validation rule is used.

 ;r;^.*_confirm$

You can write as following.

 r{^*_confirm$}
 ;;r;;^.*_confirm$

You can repeat ';' any times.

=item ;path;/path/to/where

It is as same as ;r;^/path/to/where/?$.

Note that: this is needed that ID_KEY is 'ENV_PATH_INFO'.

You can write as following.

path{/path/to/where}
;;path;;/path/to/where

You can repeat ';' any times.

=item ;GLOBAL

This is start of group, too. but 'GLOBAL' is special name.
The rule in this group is inherited by all group.

 ;GLOBAL
 
 i is number
 w is word

If you write global rule on the top of rule.
no need specify ;GLOBAL, they are parsed as GLOBAL.

 # The top of file
 
 i is number
 w is word

They will be regarded as global rule.

=item #

start from # is comment.

 # This is comment

=item sentence

 i is number

sentence has 3 parts, at least.

 Key Operator Condition

In example, 'i' is Key, 'is' is Operator and 'number' is Condition.

This means:

 return $obj->$method('i') =~/^\d+$/ + 0;

In some case, Operator can take multiple Condition.
It is depends on Operator implementation.

For example, Operator 'match' can multiple Condition.

 i match ^[a-z]+$,^[0-9]+$

When i is match former or later, it is valid.

Note that:

You CANNOT use same key with same operator.

 i is number
 i is word

=item alias = sentence

sentence is as same as above.
'alias =' effects result data structure.

First example is normal version.

Rule:

 i is number
 p is word
 z match ^\d{3}$

Result Data Structure:

 {
   'i_is'    => 0,
   'p_is'    => 0,
   'z_match' => 1,
 }

Next example is version using alias.

 id       = i is number
 password = p is word
 zip      = z match ^\d{3}$

Result Data Structure:

 {
   'id_is'        => 0,
   'password_is'  => 0,
   'zip_match'    => 1,
 }

=item Special alias name for required values

 required = name, id, password

This alias name "required" is special name and
syntax after the name, is special a bit.

This sentence means these keys/aliases, name, id and password are requried.

You can change the name "required" by required_alias_name method.

Note that: You cannot write key name if you use alias and don't use the key name elsewhere.

for example;

 foo is alpha
 alias = var is 'value'
 
 # It doesn't work correctly because alias is used instead of key name 'var'
 required = foo, var

You should write as following;

 foo is alpha
 alias = var is 'value'
 
 # It works correctly because alias is used
 required = foo, alias

But the following works correctly;

 foo is alpha
 alias = foo eq 'value'
 
 # It works correctly because key name 'foo' is used elsewhere.
 required = foo

=item Override Global Rule

You can override global rule.

 ;GLOBAL
 
 ID_KEY page
 
 i is number
 w is word
 
 ;index
 
 i is word
 w is number

If you want delete some rules in GLOBAL in 'index' group.

 ;index
 
 w is n/a
 w match ^[e-z]+$

If you want delete all GLOBAL rule in 'index' group.

 ;index

 GLOBAL is n/a

=back

=head1 FILTERS

Data::RuledValidator has filter feature.
Two way to filter values in rule.

=over 4

=item filter Key, ... with FilterName, ...

 filter tel_number with no_dash
 tel_number is num
 tel_number < ~ 10

This declaration is no relation with location.
So, following is as same mean as above.

 tel_number is num
 tel_number < ~ 10
 filter tel_number with no_dash

todo;

 need to implement filter n/a

=item Keys Operator Condition with FilterName, ...

This is temporary filter.

 tel1 = tel_number is num with no_dash
 tel2 = tel_number is num

tel1's tel_number is filtered tel_number,
but tel2's tel_number is not filtered.

But in following case, tel2 is filtered, too.

 filter tel_number with no_dash
 tel1 = tel_number is num with no_dash
 tel2 = tel_number is num

=back

=head1 OPERATORS

=over 4

=item is

 key is mail
 key is word
 key is number

'is' is something special operator.
It can be to be unavailable GLOBAL at all or about some key.

 ;;GLOBAL
 i is number
 k is value

 ;;index
 v is word

in this rule, 'index' inherits GLOBAL.
If you want not to use GLOBAL.

 ;;index
 GLOBAL is n/a
 v is word

if you want not to use key 'k' in index.

 ;;index
 k is n/a
 v is word

This inherits 'i', but doesn't inherit 'k'.

=item isnt

It is the opposite of 'is'.
but, no use to use 'n/a' in condition.

=item of

This is some different from others.
Left word is not key. number or 'all'.

 all = all of x,y,z

This is needed all of keys x, y and z.
It is no need for these value of keys to be valid.
If this key exists, it is OK.

If you need only 2 of these keys. you can write;

 2of3 = 2 of x,y,z

This is needed 2 of keys x, y or z.

If you want valid values, use of-valid instead of valid.

=item of-valid

This likes 'of'.

 all of-valid x,y,z

This is needed all of keys x, y and z.
It is needed for these value of keys to be valid.

If you need only 2 of these keys. you can write;

 2 of-valid x,y,z

This is needed 2 of keys x, y or z.

If you want valid values, use of-valid instead of 'of'.

=item in

If value is in the words, it is OK.

 key in Perl, Python, Ruby, PHP ...

This is "or" condition. If value is equal to one of them, it is OK.

=item match

This is regular expression.

 key match ^[a-z]{2}\d{5}$

If you want multiple regular expression.

 key match ^[a-z]{2}\d{5}$, ^\d{5}[a-z]{1}\d{5}$, ...

This is "or" condition. If value is match one of them, it is OK.

=item re

It is as same as 'match'.

=item has

 key has 3

This means key has 3 values.

If you want less than the number or grater than the number.
You can write;

 key has < 4
 key has > 4

=item eq (= equal)

 key eq STRING

If key's value is as same as STRING, it is valid.

You can use special string like following.

 key eq [key_name]
 key eq {data_key_name}

[key_name] is result of $obj->$method(key_name).
For the case which user have to input password twice,
you can write following rule.

 password eq [password2]

This rule means, for examle;

 $cgi->param('password') eq $cgi->param('password2');

{data_key_name} is result of $data->{data_key_name}.
For the case when you should check data from database.

 my $db_data = ....;
 if($cgi->parma('key') ne $db_data){
    # wrong!
 }

In such a case, you can write as following.

rule;

 key eq {db_data}

code;

 my $db_data = ...;
 $v->by_rule({db_data => $db_data});

=item ne (= not_equal)

 key ne STRING

If key's value is NOT as same as STRING, it is valid.
You can use special string like "eq" in above explanation.

=item E<gt>, E<gt>=

 key > 4

If key's value is greater than number 4, it is valid.
You can use '>=', too.

If you want to check length of the value,
put '~' before number as following.

 key > ~ 4

=item E<lt>, E<lt>=

 key < 5

If key's value is less than number 5, it is valid.
You can use '<=', too.

If you want to check length of the value,
put '~' before number as following.

 key < ~ 4

=item between #,#

 key between 3,5

If key's value is in the range, it is valid.

If you want to check length of the value,
put '~' before number as following.

 key between ~ 4,10

=back

=head1 HOW TO ADD OPERATOR

This module has 2 kinds of operator.

=over 4

=item normal operator

This is used in sentence.

 Key Operator Condition
     ~~~~~~~~
For example: is, are, match ...

"v is word" returns structure like a following:

 {
   v_is => 1,
   v_valid => 1,
 }

=item condition operator

This is used in sentence only when Operator is 'is/are/isnt/arent'.

 Key Operator Condition
     (is/are) ~~~~~~~~~
   (isnt/arent)

This is operator which is used for checking Value(s).
Operator should be 'is' or 'are'(these are same) or 'isnt or arent'(these are same).

For example: num, alpha, alphanum, word ...

=back

You can add these operator with 2 class method.

=over 4

=item add_operator

 Data::RuledValidator->add_operator(name => $code);

$code should return code to make closure.
For example:

 Data::RuledValidaotr->add_operator(
   'is'     =>
   sub {
     my($key, $c) = @_;
     my $sub = Data::RuledValidaotr->_cond_op($c) || '';
     unless($sub){
       if($c eq 'n/a'){
         return $c;
       }else{
         Carp::croak("$c is not defined. you can use; " . join ", ", Data::RuledValidaotr->_cond_op);
       }
     }
     return sub {my($self, $v) = @_; $v = shift @$v; return($sub->($self, $v) + 0)};
   },
 )

$key and $c is Key and Condition. They are given to $code.
$code receive them and use them as $code likes.
In example, get code ref to use $c(Data::RuledValidaotr->_cond_op($c)).

 return sub {my($self, $v) = @_; $v = shift @$v; return($sub->($self, $v) + 0)};

This is the code to return closure. To closure, 5 values are given.

 $self, $values, $alias, $obj, $method

 $self   = Data::RuledValidaotr object
 $values = Value(s). array ref
 $alias  = alias of Key
 $obj    = object given in new
 $method = method given in new

In example, first 2 values is used.

=item add_condition_operator

 Data::RuledValidator->add_condition_operator(name => $code);

$code should be code ref.
For example:

__PACKAGE__->add_condition_operator
  (
   'mail'     => sub{my($self, $v) = @_; return Email::Valid->address($v) ? 1 : 0},
  );

=back

=head1 PLUGIN

Data::RuledValidator is made with plugins (since version 0.02).

=head2 How to create plugins

It's very easy. The name of the modules plugged in this is started from 'Data::RuledValidator::Plugin::'.

for example:

 package Data::RuledValidator::Plugin::Email;
 
 use Email::Valid;
 use Email::Valid::Loose;
 
 Data::RuledValidator->add_condition_operator
   (
    'mail' =>
    sub{
      my($self, $v) = @_;
      return Email::Valid->address($v) ? 1 : ()
    },
    'mail_loose' =>
    sub{
      my($self, $v) = @_;
      return Email::Valid::Loose->address($v) ? 1 : ()
    },
   );
 
 1;

That's all. If you want to add normal_operator, use add_operator Class method.

=head1 OVERLOADING

 $valid = $validator_object;  # it is as same as $validator_object->valid;
 %valid = @$validator_object; # it is as same as %{$validator_object->result};

=head1 INTERNAL CLASS DATA

It is just a memo.

=over 4

=item %RULE

All rule for all object(which has different rule file).

structure:

 rule_name =>
  {
    _regex_group      => [],
    # For group name, regexp can be used, for no need to find rule key is regexp or not,
    # This exists.
    id_key           => [],
    # Rule has key which identify group name. this hash is {RULE_NAME => key_name}
    # why array ref?
    # for unique, we can set several key for id_key(it likes SQL unique)
    coded_rule       => [],
    # it is assemble of closure
    time             => $time
    # (stat 'rule_file')[9]
  }

=item %COND_OP

The keys are condition operator names. The values is coderef(condition operator).

=item %MK_CLOSURE

 { operator => sub{coderef which create closure} }

=item %REQUIRED

 { requred_key => undef, required_key2 => undef }

=head1 NOTE

Now, once rule is parsed, rule is change to code (assemble of closure) and
it is stored as class data.

If you use this for CGI, performance is not good.
If you use this on mod_perl, it is good idea.

I have some solution;

store code to storable file. store code to shared memory.

=head1 TODO

=over 4

=item can take 2 keys for id_key

=item More test

I need to do more test.

=back

=head1 AUTHOR

Ktat, E<lt>ktat@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2006-2007 by Ktat

This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut
