package Data::RuledValidator;

our $VERSION = '0.04';

use strict;
use warnings "all";

use Module::Pluggable search_path => [qw/Data::RuledValidator::Plugin/];

use overload 
  '""'  => \&valid,
  '@{}' => \&_result;

my %RULES;
my %COND_OP;
my %MK_CLOSURE;

sub _rules{
  my($self, $rule) = @_;
  if(@_ == 2){
    if(exists $RULES{$rule}){
      my $t = (stat $rule)[9];
      $RULES{$rule}->{time} ||= $t;
      if($RULES{$rule}->{time} < $t){
        delete $RULES{$rule}->{coded_rule};
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
  foreach my $plugin (__PACKAGE__->plugins){
    eval"CORE::require $plugin";
    if($@ and my $er = $option{import_error}){
      if($er == 1){
        warn "Plugin import Error: $plugin - $@";
      }else{
        die  "Plugin import Error: $plugin - $@";
      }
    }
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
  $option{strict} ||= 0;
  $option{rule}   ||= '';
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

sub _parse_definition{
  my($self, $defs) = @_;
  my @def;
  foreach my $def (@$defs){
    my $alias = $def =~ s/^\s*(\w+)\s*=\s*// ? $1 : '';
    my($key, $op, $cond) = split /\s+/, $def, 3;
    my $closure = $MK_CLOSURE{$op} ? $MK_CLOSURE{$op}->($key, $cond, $op) : Carp::croak("not defined operator: $op");
    push @def, [$alias, $key, $op, $closure];
  }
  return \@def;
}

sub by_sentence{
  my($self, @definition) = @_;
  @definition = @{$definition[0]} if ref $definition[0] eq 'ARRAY';
  my $defs = $self->_parse_definition(\@definition);
  return $self->_validator($defs);
}

sub _get_value{
  my($self, $last_obj, $method, $key) = @_;
  my @method =  ref $method ? @$method : $method;
  $last_obj = $last_obj->$_ foreach (@method[0 .. ($#method - 1)]);
  my $m = $method[$#method];
  return $last_obj->$m($key);
}

sub _validator{
  my($self, $defs) = @_;
  my $obj = $self->obj;
  my $method = $self->method;
  my(%result, %failure);
  my $result;
  my $all_result = 1;
  my($def_num, $ok_num);
  $self->{result} = \%result;
  $self->{failure}  = \%failure;

  foreach my $def (@$defs){
    my($alias, $key, $op, $sub) = @$def;
    Carp::craok('cannot define same combination of key and operator twice.') if exists $result{$alias . '_' . $op};
    $alias ||= $key;
    my @value = $self->_get_value($obj, $method, $key);
    if(defined $MK_CLOSURE{$op}){
      $result = $sub->($self, \@value, $alias, $obj, $method) || 0;
      unless($result{$alias . '_' . $op} = $result){
        $failure{$alias . '_' . $op} = \@value unless not @value or defined $failure{$alias . '_' . $op};
      }else{
        $result{$alias . '_valid'} = 1 unless defined $result{$alias . '_valid'};
        $result{$alias . '_valid'} &= $result;
      }
    }
    $all_result &= $result;
  }

  # $result &= (($ok_num || 0) == $def_num + 0);
  $self->{valid}  = $all_result;
  return $self;
}

sub result{
  my($self) = @_;
  return($self->{result} || {});
}

sub failure{
  my($self) = @_;
  return($self->{failure} || {});
}

sub _result{
  my($self) = @_;
  return [%{$self->{result}}];
}

sub valid{
  my($self) = @_;
  # too ugly
  return $self->{strict} ? $self->{valid} : exists $self->{failure} ? %{$self->failure} ? 0 : 1 : 0;
}

sub reset{
  my($self) = @_;
  delete $self->{$_} foreach qw/result valid failure wrong right/;
}

sub by_rule{
  my($self, $rule) = @_;
  $rule = $rule ? $self->rule($rule) : $self->rule;
  Carp::croak("need rule name")  unless $rule;
  $self->_parse_rule($rule) unless %{ $self->_rules($rule) || {} };
  my($obj, $method) = ($self->id_obj || $self->obj, $self->id_method($rule) || $self->method);
  my $id_key = $self->id_key($rule);
  my $rule_name = $id_key =~ /^ENV_(.+)$/i ? $ENV{uc($1)} : $self->_get_value($obj, $method, $id_key || ());

  my $defs = $self->_rules($rule)->{$rule_name};
  unless($defs){
    foreach my $r ($self->_regex_group($rule)){
      last if $defs = $self->_rules($rule)->{$r};
    }
  }
  $self->{rule_name} = $rule_name;
  return $self->_validator($defs || []);
}

sub _distinct_rule{
  my($self, $global_rule, $rule) = @_;
  my %has;
  my %na;
  my @new_rule;
  my @rule = (($rule->[0]->[1] eq 'GLOBAL' and $rule->[0]->[2] eq 'is' and $rule->[0]->[3] eq 'n/a') ? @$rule : (@$global_rule, @$rule)) ;
  foreach my $def (reverse @rule){
    next unless $def->[2];
    if(exists $MK_CLOSURE{$def->[2]}){
      $na{$def->[1]}->{$def->[2]} = 1 if $def->[3] eq 'n/a';
      push @new_rule, $def unless $na{$def->[1]}->{$def->[2]} or $has{$def->[1]}->{$def->[2]}++;
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
    open IN, $rule or Carp::croak "cannot open $rule";
    seek IN, 0, 0;
    @rule = <IN>;
    close IN;
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
  my $global_rule = $self->_parse_definition($rules->{GLOBAL}) || [];
  $rules->{GLOBAL} = $global_rule;
  while(my($id_name, $defs) = each %$rules){
    next if $id_name eq 'GLOBAL';
    my $rule = $self->_parse_definition($defs) || [];
    $rules->{$id_name} = $self->_distinct_rule($global_rule, $rule);
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
   $ENV{QUERY_STRING} = "page=index&i=9&v=aaaaa&k=bbbb";
 }
 
 use Data::RuledValidator;

 use CGI;
 
 my $v = Data::RuledValidator->new(obj => CGI->new, method => "param");
 print $v->by_sentence("i is num", "k is word", "v is word", "all of i,v,k");  # return 1 if valid

This means that parameter of CGI object, i is number, k is word, v is also word and needs all of i, v and k.

Next example is using following rule;

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
use rule in "index". Why using CGI object? you have to check new's arguments.
"index" rule is following:

 ;;index
 all of i, k, v

Global rule is applied as well.

 i is number
 k is word
 v is word

So it is as same as first example.

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

=back

=head1 CONSTRUCTOR

=over 4

=item new

 my $v = Data::RuledValidator->new(obj => $obj, method => $method, rule => $rule_file_location);

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

=item strict

 strict => 0

Before 0.03, Data::RuledValidator returns true with valid method,
only when all key is valid.
It means you need set "key is n/a",
if you don't use keys defined in GLOBAL in other group.
I think it is very bother.

I will change it in future. At present, if strict is 0(it's default),
if you have no wrong value, valid method returns true.
But, if you reset, it returns undef.

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

If all rule is OK, valid is 1.
If not, valid is 0.

You can get this result as following:

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

=item list_plugins

 $v->list_plugins;

list all plugins.

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

 all of x,y,z

This is needed all of keys x, y and z.
It is no need for these value of keys to be valid.
If this key exists, it is OK.

If you need only 2 of these keys. you can write;

 2 of x,y,z

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

=item eq

 key eq STRING

If key's value is as same as STRING, it is valid.

=item ne

 key ne STRING

if key's value is NOT as same as STRING, it is valid.

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

$code should return code ref.
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

 {operator => sub{coderef which create closure} }

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

Ktat, E<lt>atusi@pure.ne.jpE<gt>

=head1 COPYRIGHT

Copyright 2006 by Ktat

This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut
