package Data::RuledValidator::Filter;

use strict;
use warnings qw/all/;
use Data::RuledValidator::Util;

our $VERSION = 0.01;

sub trim{
  my($self, $v) = @_;
  $$v =~ s/^\s*//o;
  $$v =~ s/\s*$//o;
}

sub no_dash{
  my($self, $v) = @_;
  $$v =~ s/\-//go;
}

sub lc{
  my($self, $v) = @_;
  $$v = lc($$v);
}

sub uc{
  my($self, $v) = @_;
  $$v = uc($$v);
}

1;

=head1 Name

Data::RuledValidator::Filter - filters

=head1 Description

=head1 Synopsys

=head1 Author

Ktat, E<lt>ktat@cpan.orgE<gt>

=head1 Copyright

Copyright 2006-2007 by Ktat

This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut
