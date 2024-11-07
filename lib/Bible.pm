package Tarot;

use strict;
use warnings;

use Data::Dumper::Compact qw(ddc);
use List::Util qw(first sample shuffle);
use Time::HiRes qw(time);

use constant MAJOR_ARCANA => (
  'fool',
  'magician',
  'priestess',
  'empress',
  'emperor',
  'hierophant',
  'lovers',
  'chariot',
  'strength',
  'hermit',
  'wheel of fortune',
  'justice',
  'hanged man',
  'death',
  'temperance',
  'devil',
  'tower',
  'star',
  'moon',
  'sun',
  'judgment',
  'world',
);
use constant MINOR_ARCANA_SUITS => (
  'wands',
  'cups',
  'swords',
  'pentacles',
);

sub build_cards {
  return (
    MAJOR_ARCANA,
    (
      map {
        my $suit = $_;
        map { "$_ of $suit" } 'ace', 2 .. 10, qw(page knight queen king)
      } MINOR_ARCANA_SUITS
    ),
  );
}

sub build_deck {
  my @cards = build_cards();
  my %deck;
  my $n = 0;
  for my $card (@cards) {
    $deck{cards}{$card} = {
      name   => $card,
      n      => $n, # original card number
      p      => $n, # position
      o      => 0,  # orientation
      chosen => 0,  # has been chosen
      file   => card_file($card),
    };
    $n++;
  }
  return \%deck;
}

sub shuffle_deck {
  my ($deck, $orient) = @_;
  my @shuffled = shuffle(keys $deck->{cards}->%*);
  my $n = sprintf '%.0f', @shuffled * $orient / 100; # get pecentage
  my @sample = sample($n, @shuffled);
  my $i = 0;
  for my $card (@shuffled) {
    my $orientation = (first { $_ eq $card } @sample)
      ? !$deck->{cards}{$card}{o} : $deck->{cards}{$card}{o};
    $deck->{cards}{$card}->{p} = $i;
    $deck->{cards}{$card}->{o} = $orientation;
    $i++;
  }
}

sub cut_deck {
  my ($deck, $n) = @_;
  my @cards = keys $deck->{cards}->%*;
  $n //= int(@cards / 2); # default half of deck
  die "N must be between 0 and ", $#cards - 1, "\n"
    if $n < 0 || $n > $#cards - 1;
  my @ordered = sort { $deck->{cards}{$a}{p} <=> $deck->{cards}{$b}{p} } @cards;
  my @cut = (
    @ordered[ $n + 1 .. $#ordered ],
    @ordered[ 0 .. $n ],
  );
  my $i = 0;
  for my $card (@cut) {
    $deck->{cards}{$card}{p} = $i;
    $i++;
  }
}

sub choose {
  my ($deck, $n) = @_;
  $n //= int rand keys $deck->{cards}->%*;
  my $chosen;
  for my $card (keys $deck->{cards}->%*) {
    next if $deck->{cards}{$card}{chosen};
    next unless $deck->{cards}{$card}{p} == $n;
    $chosen = $card;
    last;
  }
  if ($chosen) {
    $deck->{cards}{$chosen}{chosen} = 1;
    return $deck->{cards}{$chosen};
  }
  else {
    warn 'No card chosen';
    return;
  }
}

sub spread {
  my ($deck, $n) = @_;
  $n ||= 3;
  my @spread;
  # not the most efficient loop...
  for my $draw (1 .. $n) {
    my @non_chosen = map { $deck->{cards}{$_}{p} }
      grep { $deck->{cards}{$_}{chosen} == 0 }
        keys $deck->{cards}->%*;
    my $choice = $non_chosen[ int rand @non_chosen ];
    my $card = defined $choice ? choose($deck, $choice) : undef;
    push @spread, $card if $card;
  }
  return \@spread;
}

sub clear {
  my ($deck) = @_;
  for my $card (keys $deck->{cards}->%*) {
    $deck->{cards}{$card}{chosen} = 0;
  }
}

sub card_file {
  my ($card) = @_;
  my $filename = '/images/' . $card . '.jpeg';
  return $filename;
}

sub get_chosen {
  my ($deck, $choices) = @_;

  my @chosen;

  for my $n (@$choices) {
    my $card = ( first { $deck->{cards}{$_}{p} == $n } keys $deck->{cards}->%* )[0];
    push @chosen, $deck->{cards}{$card} if $card && exists $deck->{cards}{$card};
  }

  return \@chosen;
}

1;
