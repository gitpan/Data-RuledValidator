package Data::RuledValidator::Closure;

use strict;

my $parent = 'Data::RuledValidator';

$parent->add_operator
  (
   '>'      => sub {my($key, $c) = @_; return sub{my($self, $v) = @_; return ($v >  $c + 0)}},
   '<'      => sub {my($key, $c) = @_; return sub{my($self, $v) = @_; return ($v <  $c + 0)}},
   '>='     => sub {my($key, $c) = @_; return sub{my($self, $v) = @_; return ($v >= $c + 0)}},
   '<='     => sub {my($key, $c) = @_; return sub{my($self, $v) = @_; return ($v <= $c + 0)}},
   'eq'     => sub {my($key, $c) = @_; return sub{my($self, $v) = @_; return ($v eq $c + 0)}},
   'ne'     => sub {my($key, $c) = @_; return sub{my($self, $v) = @_; return ($v ne $c + 0)}},
   're'     => sub {my($key, $c) = @_; return sub{my($self, $v) = @_; return ($v =~ qr/$c/ + 0)}},
   'has'    => sub {my($key, $c) = @_; return sub{my($self, $v) = @_; return @$v == $c}},
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
           ++$ok if $self->ok($k);
           ++$n;
         }
         return $key eq 'all' ? ($ok == $n + 0) : ($ok == $key + 0) ;
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
           ++$ok if $obj->$method($k);
           ++$n;
         }
         return $key eq 'all' ? ($ok == $n + 0) : ($ok == $key + 0) ;
       }
     },
   'is'     =>
   sub {
     my($key, $c) = @_;
     my $sub = $parent->_cond_op($c) || '';
     unless($sub){
       if($c eq 'n/a'){
         return $c;
       }else{
         Carp::croak("$c is not defined. you can use; " . join ", ", $parent->_cond_op);
       }
     }
     return sub {my($self, $v) = @_; $v = shift @$v; return($sub->($self, $v) + 0)};
   },
   'match'  =>
   sub {
     my($key, $c) = @_;
     my @regex = split /\s+/, $c;
     return sub{
       my($self, $v) = @_;
       $v = shift @$v;
       my $ok = 1;
       foreach my $regex (@regex){
         $ok &= $v =~ qr/$regex/ or last;
       }
       return $ok;
     };
   },
   'isnt'   =>
   sub {
     my($key, $c) = @_;
     my $sub = $parent->_cond_op($c);
     unless($sub){
       Carp::croak("$c is not defined. you can use; " . join ", ", $parent->_cond_op);
     }
     return sub {my($self, $v) = @_; $v = shift @$v;return(! $sub->($self, $v) + 0)};
   },
   'are'     =>
   sub {
     my($key, $c) = @_;
     my $sub = $parent->_cond_op($c);
     unless($sub){
       Carp::croak("$c is not defined. you can use; " . join ", ", $parent->_cond_op);
     }
     return
       sub {
         my($self, $v) = @_;
         my $ok;
         foreach my $val (@$v){
           $ok &= $sub->($self, $val) or last;
         }
         return $ok;
       };
   },
   'arent'   =>
   sub {
     my($key, $c) = @_;
     my $sub = $parent->_cond_op($c);
     unless($sub){
       Carp::croak("$c is not defined. you can use; " . join ", ", $parent->_cond_op);
     }
     return
       sub {
         my($self, $v) = @_;
         my $ok = 0;
         foreach my $val (@$v){
           $ok |= $sub->($self, $val) or last;
         }
         return ! $ok;
       };
   },
   'len'    =>
   sub {
     my($key, $c) = @_;
     my($from, $to) = split(',', $c);
     $from ||= 0;
     $to   ||= 0;
     if($from and $to){
       return sub {my($self, $v) = @_; $v = shift @$v; return($from <= length($v) and length($v) <= $to + 0)};
     }elsif($from){
       return sub {my($self, $v) = @_; $v = shift @$v; return($from <= length($v) + 0)};
     }elsif($to){
       return sub {my($self, $v) = @_; $v = shift @$v; return(length($v) >= $to + 0)};
     }else{
       Carp::croak('len need $from and/or $to; one of their value must be more than 1.');
     }
   },
  );

1;
__END__

=pod

=head1 Name

Data::RuledValidator::Closure - closure using by Data::RuledValidator

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
