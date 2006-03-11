use Test::More 'no_plan';

BEGIN {
  use_ok('Data::RuledValidator');
  $ENV{REQUEST_METHOD} = "GET";
  $ENV{QUERY_STRING} = "page=index&i=9&v=aaaaa&k=bbbb";
}

use CGI;

my $q = new CGI;
my $v = Data::RuledValidator->new(obj => $q, method => 'param');
ok(ref $v, 'Data::RuledValidator');
is($v->obj, $q);
is($v->method, 'param');

# correct rule
ok($v->by_sentence('page is word', 'i is num', 'v is word', 'k is word', 'all of i k v'));
ok($v->ok('page_is'));
ok($v->ok('i_is'));
ok($v->ok('k_is'));
ok($v->ok('all_of'));
ok($v->ok('page_valid'));
ok($v->ok('i_valid'));
ok($v->ok('k_valid'));
ok($v->ok('all_valid'));
ok($v->valid);
$v->reset;
ok(! $v);

# mistake rule
ok(not $v->by_sentence('page is num', 'i is num', 'v is num', 'k is num', 'all of i k v x'));
ok(not $v->ok('page_is'));
ok($v->ok('i_is'));
ok(not $v->ok('k_is'));
ok(not $v->ok('all_of'));
ok(not $v->ok('page_valid'));
ok(ok $v->ok('i_valid'));
ok(not $v->ok('k_valid'));
ok(not $v->ok('all_valid'));
ok(not $v->valid);
$v->reset;
ok(! $v);

# create alias
Data::RuledValidator->create_alias_operator('isis', 'is');
Data::RuledValidator->create_alias_cond_operator('number', 'num');
ok(not $v->by_sentence('page is num', 'i isis num', 'v is number', 'k isis num', 'all of i k v x'));
ok(not $v->ok('page_isis'));
ok($v->ok('i_isis'));
ok(not $v->ok('k_isis'));
ok(not $v->ok('all_of'));
ok(not $v->ok('page_valid'));
ok(ok $v->ok('i_valid'));
ok(not $v->ok('k_valid'));
ok(not $v->ok('all_valid'));
ok(not $v->valid);
$v->reset;
ok(! $v);

=functions
add_operator
add_condition_operator
to_obj
id_key
result
reset
get_rule
by_rule
=cut
