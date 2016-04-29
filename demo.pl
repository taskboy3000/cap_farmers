# Get the gist of the game using a few dumb bots
use strict;
use warnings;
use Time::HiRes;
use Data::Dumper;


package World;

sub new {
    my $class = shift;
    my %self = @_;
    
    $self{caps}   = 100;
    $self{energy} = 100;
    $self{ore}    = 100;
    bless \%self, $class;
    \%self;
}

sub fn {
    my ($self, $x) = @_;
    $x *= 1.0;
    return ($x**2.0) - (4.0 * $x) + 4.0
}

sub unit_price {
    my ($self, $product) = @_;

    my $supply = $self->{$product};
    # Map the supply into the domain of the demand curve (200 units)
    my $over_abundance = 200.0;
    my $base_cost = 10.0;
    
    if ($supply > $over_abundance) {
        print "World glut of $product: $supply units available\n";
        $supply = $over_abundance;
    }

    if ($supply < 0) {
        $supply = 0;
    }

    if ($supply < 1.0) {
        printf "World shortage of $product: %0.2f units available\n", $supply;
    }
    
    # Range of X values 0 - 2
    my $scalar = $self->fn(2.0 * ($supply / $over_abundance));
    return $scalar * $base_cost;
}

package Actor;
our $ID = 0;
sub new {
    my $class = shift;
    my %self = @_;
    $self{id} = $Actor::ID++;
    $self{caps} = 0;
    $self{energy} = 0;
    $self{ore} = 0;
    bless \%self, $class;
    \%self;
}

sub sell {
    my ($self, $product) = @_;

    for my $product ('ore', 'energy') {
        my $want = int(rand() * 30);
        while ($want > $self->{$product}) {
            $want = int(rand() * 30);
        }
        
        next if $want < 1;
        
        $self->{$product} -= $want;
        my $unit_price = $self->{world}->unit_price($product);
        $self->{caps} += $unit_price * $want; # fiat money
        printf $self->{id} . ": sells $want units of $product \@ %0.2f caps/unit\n", $unit_price;
    }

}

sub buy {
    my ($self, $product) = @_;
    
    for my $product ('ore', 'energy') {
        my $want = int(rand() * 40);
        while ($want > $self->{world}->{$product}) {
            $want = int(rand() * 30);
        }
        
        $self->{world}->{$product} -= $want;
        my $unit_price = $self->{world}->unit_price($product);
        if (($unit_price * $want) < $self->{caps}) {
            printf $self->{id} . ": buys $want units of $product \@ %0.2f caps/unit\n", $unit_price;
            $self->{caps} -= $unit_price * $want;
        } else {
           print($self->{id} . ": cannot buy $want units of $product. Not enough caps\n");
        }
    }
}


sub produce {
    my ($self) = @_;

    for my $product ('ore', 'energy') {
        my $harvest = int(rand() * 10);
        $self->{$product} += $harvest;
        print $self->{id} . ": produced $harvest units of $product\n";
    }
    
}


package main;

Main();

sub Main {
    my $world = World->new();
    my @actors;
    for (0..3) {
        push @actors, Actor->new(world => $world);
    }

    my $week = 0;
    while (1) {
        printf "=====Week %03d====\n", $week++;
        
        for my $actor (@actors) {
            $actor->produce;
            $actor->sell;
            print "----\n";
        }
        
        for my $actor (@actors) {
            $actor->buy;
            print "----\n";
        }
        
        sleep(3);
    }
}

1;
