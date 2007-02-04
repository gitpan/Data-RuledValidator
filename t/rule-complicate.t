use Test::More 'no_plan';

BEGIN {
  use_ok('Data::RuledValidator');
}
use Data::Dumper;
use strict;
use File::Copy ();

my %query =
  (
   page        => 'registration'                ,
   first_name  => 'Atsushi'                     ,
   last_name   => 'Kato'                        ,
   age         => 29                            ,
   sex         => 'male'                        ,
   hobby       => [qw/programming outdoor camp/],
   birth_year  => 1777,
   birth_month => 1,
   birth_day   => 1,
   favorite    => [qw/books music/],
   favorite_books  => ["Nodame", "Ookiku Furikabutte"],
   favorite_music  => ["Paul Simon"],
   must_select3    => [qw/1 2 3/],
   must_select1    => [qw/1/],
   must_gt_1000    => 1001,
   must_lt_1000    => 999,
   must_in_1_10    => [qw/8 9 7 4 3/],
   length_in_10    => '1234567890',
   regex           => 'abcdef',
);

my $q = bless \%query, 'main';

sub p{
  my($self, $k, $v) = @_;
  return
    @_ == 3 ? $self->{$k} = $v :
    @_ == 2 ? ref $self->{$k} ?
              wantarray       ? @{$self->{$k}} : $self->{$k}->[0] : $self->{$k} :
              keys %{$self};
}

my $v = Data::RuledValidator->new(obj => $q, method => 'p', rule => "t/validator_complicate.rule");
ok(ref $v, 'Data::RuledValidator');
is($v->rule, "t/validator_complicate.rule");

# registration
ok($v->by_rule);
ok($v);
$v->reset;


