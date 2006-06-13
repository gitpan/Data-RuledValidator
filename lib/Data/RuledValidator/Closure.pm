package Data::RuledValidator::Closure;

use strict;
use warnings qw/all/;

our $VERSION = 0.01;

my $parent = 'Data::RuledValidator';

use constant 
  {
    IS => sub { # now this is not used, using are instead.
      my($key, $c) = @_;
      my $sub = $parent->_cond_op($c) || '';
      unless($sub){
        if($c eq 'n/a'){
          return $c;
        }else{
          Carp::croak("$c is not defined. you can use; " . join ", ", $parent->_cond_op);
        }
      }
      return sub {my($self, $v) = @_; $v = shift @$v; return ($sub->($self, $v) + 0)};
    },
    ISNT => sub { # now this is not used, using are instead.
      my($key, $c) = @_;
      my $sub = $parent->_cond_op($c);
      unless($sub){
        Carp::croak("$c is not defined. you can use; " . join ", ", $parent->_cond_op);
      }
      return sub {my($self, $v) = @_; $v = shift @$v; return(! $sub->($self, $v) + 0)};
    },
    ARE => sub {
      my($key, $c) = @_;
      unless($c =~/,/){
        # single condition
        my $sub = $parent->_cond_op($c) || '';
        unless($sub){
          if($c eq 'n/a'){
            return $c;
          }else{
            Carp::croak("$c is not defined. you can use; " . join ", ", $parent->_cond_op);
          }
        }
        return sub {my($self, $v) = @_; return(_vand($self, $key, $c, $v, sub{my($self, $v) = @_; $sub->($self, $v)}))};
      }else{
        my @c = split /\s*,\s*/, $c;
        my @sub = grep $_, map $parent->_cond_op($_), @c;
        unless(@sub == @c){
          Carp::croak("some of '@c' are not defined. you can use; " . join ", ", $parent->_cond_op);
        }
        return sub {my($self, $v) = @_; return(_vand($self, $key, $c, $v, sub{my($self, $v) = @_; foreach (@sub){$_->($self, $v) and return 1} }))};
      }
    },
    ARENT => sub {
      my($key, $c) = @_;
      unless($c =~/,/){
        # single condition
        my $sub = $parent->_cond_op($c) || '';
        unless($sub){
          if($c eq 'n/a'){
            return $c;
          }else{
            Carp::croak("$c is not defined. you can use; " . join ", ", $parent->_cond_op);
          }
        }
        return sub {my($self, $v) = @_; return(_vand($self, $key, $c, $v, sub{my($self, $v) = @_; ! $sub->($self, $v)}))};
      }else{
        my @c = split /\s*,\s*/, $c;
        my @sub = grep $parent->_cond_op($_), @c;
        unless(@sub == @c){
          Carp::croak("some of '@c' are not defined. you can use; " . join ", ", $parent->_cond_op);
        }
        return sub {my($self, $v) = @_; return(_vand($self, $key, $c, $v, sub{my($self, $v) = @_; ! (grep $_->($self, $v), @sub) == @sub}))};
      }
    },
    MATCH => sub {
      my($key, $c) = @_;
      my @regex = split /\s+/, $c;
      my $sub = sub{
        my($self, $v) = @_;
        my $ok = 0;
        foreach my $regex (@regex){
          $ok |= $v =~ qr/$regex/ or last;
        }
        return $ok;
      };
      return sub {my($self, $v) = @_; return(_vor($self, $key, $c, $v, sub{my($self, $v) = @_; $sub->($self, $v)}))};
    },
    GT => sub {
      my($key, $c, $op) = @_;
      my $sub;
      if($op eq '>='){
        if($c =~s/\s*~\s*//){
          $sub = sub{my($self, $v) = @_; return ((length($v) >=  $c) + 0)}
        }else{
          $sub = sub{my($self, $v) = @_; return (($v >=  $c) + 0)}
        }
      }else{
        if($c =~s/\s*~\s*//){
          $sub = sub{my($self, $v) = @_; return ((length($v) >  $c) + 0)}
        }else{
          $sub = sub{my($self, $v) = @_; return (($v >  $c) + 0)}
        }
      }
      return sub{my($self, $v) = @_; _vand($self, $key, $c, $v, $sub)};
    },
    LT => sub {
      my($key, $c, $op) = @_;
      my $sub;
      if($op eq '<='){
        if($c =~s/\s*~\s*//){
          $sub = sub{my($self, $v) = @_; return ((length($v) <=  $c) + 0)}
        }else{
          $sub = sub{my($self, $v) = @_; return (($v <=  $c) + 0)}
        }
      }else{
        if($c =~s/\s*~\s*//){
          $sub = sub{my($self, $v) = @_; return ((length($v) <  $c) + 0)}
        }else{
          $sub = sub{my($self, $v) = @_; return (($v <  $c) + 0)}
        }
      }
      return  sub{my($self, $v) = @_; _vand($self, $key, $c, $v, $sub)};
    },
    BETWEEN => sub {
      my($key, $c, $op) = @_;
      my $sub;
      if($c =~s/\s*~\s*//){
        my($start, $end) = split(/,/, $c);
        $sub = sub{my($self, $v) = @_; return (($start <= length($v) and length($v) <=  $end) + 0)}
      }else{
        my($start, $end) = split(/,/, $c);
        $sub = sub{my($self, $v) = @_; return (($start <= $v and $v <=  $end) + 0)}
      }
      return  sub{my($self, $v) = @_; _vand($self, $key, $c, $v, $sub)};
    },
  };

# '&' validation for multiple values
sub _vand{
  my ($self, $key, $c, $val, $sub) = @_;
  my $ok = 1;
  foreach my $v (@$val){
    my $_ok = 1;
    if($_ok = $sub->($self, $v) ? 1 : 0){
      push @{$self->{rigth}->{"${key}_$c"} ||= []},  $v;
    }else{
      push @{$self->{wrong}->{"${key}_$c"} ||= []},  $v;
    }
    $ok &= $_ok;
  }
  return $ok;
}

# '|' validation for multiple values
sub _vor{
  my ($self, $key, $c, $val, $sub) = @_;
  my $ok = 0;
  foreach my $v (@$val){
    my $_ok = 0;
    if($_ok = $sub->($self, $v) ? 1 : 0){
      push @{$self->{rigth}->{"${key}_$c"} ||= []},  $v;
    }else{
      push @{$self->{wrong}->{"${key}_$c"} ||= []},  $v;
    }
    $ok |= $_ok;
  }
  return $ok;
}

$parent->add_operator
  (
   'is'     => ARE,
   'isnt'   => ARENT,
   'are'    => ARE,
   'arent'  => ARENT,
   're'     => MATCH,
   'match'  => MATCH,
   '>'      => GT,
   '>='     => GT,
   '<'      => LT,
   '<='     => LT,
   'between'=> BETWEEN,
   'eq'     => sub {my($key, $c) = @_; return sub{my($self, $v) = @_; return (($v eq $c) + 0)}},
   'ne'     => sub {my($key, $c) = @_; return sub{my($self, $v) = @_; return (($v ne $c) + 0)}},
   'has'    =>
   sub {
     my($key, $c) = @_;
     if(my($e, $n) = $c =~m{^\s*([<>])?\s*(\d+)$}){
       $e ||= '';
       if($e eq '<'){
         return sub{my($self, $v) = @_; return @$v < $n}
       }elsif($e eq '>'){
         return sub{my($self, $v) = @_; return @$v > $n}
       }else{
         return sub{my($self, $v) = @_; return @$v == $n}
       }
     }else{
       Carp::croak("$c is not +# or -#(example +3 or -3); " . join ", ", $parent->_cond_op);
     }
   },
   'of-valid' =>
   sub {
     my($key, $c) = @_;
     my @cond = split(/[\s,]+/, $c);
     return
       sub {
         my($self, $values, $alias, $obj, $method) = @_;
         my $ok = 0;
         my $n  = 0;
         foreach my $k (@cond){
           next unless $k;
           ++$ok if $self->valid_ok($k);
           ++$n;
         }
         return $key eq 'all' ? ($ok == $n) + 0 : ($ok == $key) + 0 ;
       }
     },
   'of'     =>
   sub {
     my($key, $c) = @_;
     my @cond = split(/[\s,]+/, $c);
     return
       sub {
         my($self, $values, $alias, $obj, $method) = @_;
         my $ok = 0;
         my $n  = 0;
         foreach my $k (@cond){
           next unless $k;
           ++$ok if defined $obj->$method($k);
           ++$n;
         }
         return $key eq 'all' ? ($ok == $n) + 0 : ($ok == $key) + 0 ;
       }
     },
  );

1;
__END__

=pod

=head1 Name

Data::RuledValidator::Closure - sobroutines to create closure using by Data::RuledValidator

=head1 Description

=head1 Synopsys

=head1 Author

Ktat, E<lt>atusi@pure.ne.jpE<gt>

=head1 Copyright

Copyright 2006 by Ktat

This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut
