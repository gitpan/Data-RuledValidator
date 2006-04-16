package Data::RuledValidator;

our $VERSION = '0.02';

use strict;
use warnings "all";

use Module::Pluggable search_path => [qw/Data::RuledValidator::Plugin/];

use overload 
  '""'  => \&valid,
  '@{}' => \&_result;

my %RULES;
my %RULE_ID_KEY;

# condition operator
my %COND_OP;

# create closure
my %MK_CLOSURE;

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
      Carp::croak("$op has alredy defined as normal operator.");
    }
    $MK_CLOSURE{$op} = $sub;
  }
}

sub add_condition_operator{
  my($self, %op_sub) = @_;
  while(my($op, $sub) = each %op_sub){
    if($COND_OP{$op}++){
      Carp::croak("$op is alredy defined as condition operator.");
    }
    $COND_OP{$op} = $sub;
  }
}

sub create_alias_operator{
  my($self, $alias, $original) = @_;
  if($MK_CLOSURE{$alias}){
    Carp::croak("$alias has alredy defined as context/normal operator.");
  }elsif(not $MK_CLOSURE{$original}){
    Carp::croak("$original is not defined as context/normal operator.");
  }
  $MK_CLOSURE{$alias} = $MK_CLOSURE{$original};
}

sub create_alias_cond_operator{
  my($self, $alias, $original) = @_;
  if($COND_OP{$alias}++){
    Carp::croak("$alias has alredy defined as condition operator.");
  }
  $COND_OP{$alias} = $COND_OP{$original};
}

sub new{
  my($class, %option) = @_;
  $option{result} = {};
  $option{valid}  = 0;
  $option{rule} ||= '';
  my $o = bless \%option, $class;
  return $o;
}

sub list_plugins{
  my($self) = @_;
  return $self->plugins;
}

sub obj{ shift()->{obj} };

sub to_obj{ shift()->{to_obj} };

sub method{ shift()->{method} };

sub id_key{ my($self, $rule) = @_; $RULE_ID_KEY{$rule} };

sub _parse_definition{
  my($self, $defs) = @_;
  my @def;
  foreach my $def (@$defs){
    my $alias = $def =~ s/^\s*(\w+)\s*=\s*// ? $1 : '';
    my($key, $op, $cond) = split /[\s\-]+/, $def, 3;
    my $closure = $MK_CLOSURE{$op} ? $MK_CLOSURE{$op}->($key, $cond) : Carp::croak("not defined operator: $op");
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

sub _validator{
  my($self, $defs) = @_;
  my $obj = $self->obj;
  my $method = $self->method;
  my %result;
  my $result;
  my $all_result = 1;
  my($def_num, $ok_num);

  foreach my $def (@$defs){
    my($alias, $key, $op, $sub) = @$def;
    $alias ||= $key;
    my @value = $obj->$method($key);
    if(defined $MK_CLOSURE{$op}){
      $result = $sub->($self, \@value, $alias, $obj, $method) || 0;
      $result{$alias . '_' . $op} = $result;
      $result{$alias . '_valid'} = 1 unless defined $result{$alias . '_valid'};
      $result{$alias . '_valid'} &= $result;
    }
    $all_result &= $result;
  }

  # $result &= (($ok_num || 0) == $def_num + 0);
  $self->{result} = \%result;
  $self->{valid} = $all_result;
  return $self;
}

sub result{
  my($self) = @_;
  return($self->{result} || {});
}

sub _result{
  my($self) = @_;
  return [%{$self->{result}}];
}

sub valid{
  my($self) = @_;
  return $self->{valid};
}

sub reset{
  my($self) = @_;
  delete $self->{$_} foreach qw/result valid/;
}

sub get_rule {
  my($self, $rule, $rule_name) = @_;
  return $RULES{$rule}->{$rule_name};
}

sub by_rule{
  my($self, $rule) = @_;
  $rule ||= $self->{rule};
  Carp::croak("need rule name")  unless $rule;
  $self->_parse_rule($rule) unless defined $RULES{$rule};
  my($obj, $method) = ($self->obj, $self->method);
  my $id_key = $self->id_key($rule);
  my $rule_name = $id_key =~/^ENV_(.+)$/ ? $ENV{$1} : $obj->$method($id_key);
  return $self->_validator($self->get_rule($rule, $rule_name) || []);
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
  my $rules = $RULES{$rule} ||= {};
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
    next unless $line or $line =~/^\s*#/;
    if($line =~s/^ID_KEY\s+//){
      $RULE_ID_KEY{$rule} = $line;
    }elsif($line =~/^\s*\{\s*([\w\/]+)\s*\}\s*$/ or $line =~m|^\s*;+\s*([\w\/]+)\s*$|){
      # page name
      $id_name = $1;
      $rules->{$id_name} ||= [];
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

use Data::RuledValidator::Closure;

1;
__END__

=pod

=head1 NAME

Data::RuledValidator - data validator with rule

=head1 DESCRIPTION

Data::RuledValidator is validator of data.
This needs rule which is readable by not programmer ... so it is like specification.

=head1 WHAT FOR ?

One programmer said;

 specification is in code, so documentation is not needed.

Another programmer said;

 code is specification, so if I write specification, it is against DRY.

It is execuse of them. They may dislike to write documents, they may be not good at writinng documents,
and/or they may think validation check is trivial task.
But, if specification is used by programming and we needn't write program,
they will start to write specification. And, at last, we need specification.

=head1 SYNOPSYS

You can use this without rule file.

 BEGIN{
   $ENV{REQUEST_METHOD} = "GET";
   $ENV{QUERY_STRING} = "page=index&i=9&v=aaaaa&k=bbbb";
 }
 
 use Data::RuledValidator;

 use CGI;
 
 my $v = Data::RuledValidator->new(obj => CGI->new, method => "param");
 print $v->by_sentence("i is num", "k is word", "v is word", "all of i,v,k");  # return 1 if valid

This means that parameater of CGI object, i is number, k is word, v is also word and needs all of i, v and k.

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

This is as nealy same as first example.
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

Condition is the condition for Operator to judge whether Value(s) is/are valid or not.

=back

=head1 USING OPTION

When using Data::RuledValidator, you can use option.

=over 4

=item import_error

This defines behavior when plugin is not inported correctly.

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

 Data::RuledValidator->new(obj => $obj, method => $method);

If you use "by_sentence" and/or you use "by_rule" with argument, no need to use rule.

=back

=head1 METHOD for VALIDATION

=over 4

=item by_sentence

 $v->by_sentence("i is number");

arguments is rule.
You can write multiple sentence.
It returnes $v object.

=item by_rule

 $v->by_rule();
 $v->by_rule($rule);

If $rule is ommitted, using the file which is specified in new.
It returnes $v object.

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

The result of validation check.
The returned value is 1 or 0.

You can get this result as following:

 $result = $v;

=item reset

 $v->reset();

The result of validation check is resetted.

=back

=head1 RULE SYNTAX

Rule Syntax is very simple.

=over 4

=item ID_KEY Key

The right value is key which is pased to Object->Method.
The returned value of Object->Method(Key) is used to identify id_key_value.

 ID_KEY page

=item ;id_key_value

start from ; is start of group and the end of this group is the line before next ';'.
If the value of Object->Method(ID_KEY) is equal id_key_value, this group validation rule is used.

 ;index

=item ;r;^id_key_value$ (not yet implemented)

This is start of group, too.
If the value of Object->Method(ID_KEY) is match id_key_value, this group validation rule is used.

 ;r; ^.*_confirm$

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

They will be reagrded as global rule.

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

In some case, Operatior can take multiple Condition.
It is depends on Operator implementation.

For example, Operator 'match' can multiple Condition.

 i match ^[a-z]+$ ^[0-9]+$

Note that:

You cannot use same operator for same key.

 i is number
 i is word

=item alias = sentence

sentence is as same as above.
alias = effects result data structure.

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

 GLOABAL is n/a

=back

=head1 OPERATORS

=over 4

=item eq

=item match

=back

=head1 HOW TO ADD OPERATOR

This module has 2 kinds of operator.

=over 4

=item normal operator

This is used in sentence.

 Key Operator Condition
     ~~~~~~~~
For example: is, are, match ...

"v is word" returns strucutre like a following:

 {
   v_is => 1,
   v_valid => 1,
 }

=item condition operator

This is used in sentence.

 Key Operator Condition
              ~~~~~~~~~
This is operator which is used for checking Value(s).

For example: num, alpha, alphanum ...

=back

You can add these opeartor with 2 class method.

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
         Carp::croak("$c is not defined. you can use; " . join ", ", Data::RuledValidaotr->cond_op);
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

Data::RuledValidator is made with plugins (from version 0.02).

=head2 How to create plugins

It's very easy. The name of the modules plugged in this is started from 'Data::RuledValidator::'.

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

=head1 NOTE

Now, once rule is parsed, rule is change to code (assemble of closure) and
it is stored as class data.

If you use this for CGI, performance is not good.
If you use this on mod_perl, it is good idea.

I have some solution;

store code to storable file. store code to shared memory.

=head1 TODO

=over 4

=item can 2 keys for id_key

=item More test

I need more test.

=back

=head1 AUTHOR

Ktat, E<lt>atusi@pure.ne.jpE<gt>

=head1 COPYRIGHT

Copyright 2006 by Ktat

This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut
