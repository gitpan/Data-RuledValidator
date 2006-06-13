package Data::RuledValidator::Plugin::Core;

use strict;
use warnings;
use Carp;
use Email::Valid ();

our $VERSION = '0.02';

Data::RuledValidator->add_condition_operator
  (
   'num'      => sub{my($self, $v) = @_; return $v =~/^\d+$/},
   'alpha'    => sub{my($self, $v) = @_; return $v =~/^[a-zA-Z]+$/},
   'alphanum' => sub{my($self, $v) = @_; return $v =~/^[a-zA-Z0-9]+$/},
   'word'     => sub{my($self, $v) = @_; return $v =~/^\w+$/},
   'any'      => sub{my($self, $v) = @_; return defined $v},
   'null'     => sub{my($self, $v) = @_; return not defined $v or $v eq ''},
  );

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Data::RuledValidator::Plugin::Core - Data::RuldedValidator core plugins

=head1 SYNOPSIS

=head1 DESCRIPTION

=head2 EXPORT

=head1 SEE ALSO

=head1 COPYRIGHT AND LICENSE


=head1 AUTHOR

Ktat, E<lt>atusi@pure.ne.jpE<gt>

=head1 COPYRIGHT

Copyright 2006 by Ktat

This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut
