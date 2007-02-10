package DRV_Test;

sub new{
  shift;
  my %query = @_;
  bless \%query;
}

sub p{
  my($self, $k, $v) = @_;
  return
    @_ == 3 ? $self->{$k} = $v :
    @_ == 2 ? ref $self->{$k} ?
              wantarray       ? @{$self->{$k}} : $self->{$k}->[0] : $self->{$k} :
              keys %{$self};
}

1;
