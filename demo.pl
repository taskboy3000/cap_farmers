# Get the gist of the game using a few dumb bots
use strict;
use warnings;
use Time::HiRes;
use Data::Dumper;
use List::Util ('all');

#--------------------------------
package World;
use Term::ANSIColor;

sub new {
    my $class = shift;
    my %self = @_;
    
    # $self{caps}   = 100;
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
    my ($self, $product, $quite_mode) = @_;
    $quite_mode ||= 0;
    
    my @report;

    my $supply = $self->{$product};
    # Map the supply into the domain of the demand curve (200 units)

    my $over_abundance = 200.0;
    my $base_cost = 10.0;

    if ($supply > $over_abundance) {
        push @report,
          color("bold white")
          . "World glut of $product: $supply units available"
          . color("reset");
          
        $supply = $over_abundance;
    }

    if ($supply < 0) {
        $supply = 0;
    }

    if ($supply < 1.0) {
        push @report,
          color("bold white")
          . sprintf("World shortage of $product: %0.2f units available", $supply)
          . color("reset");
    }
    
    # Range of X values 0 - 2
    my $scalar = $self->fn(2.0 * ($supply / $over_abundance));

    $self->msg(@report) unless $quite_mode;
                    
    return $scalar * $base_cost;
}

sub has_shortage {
    my ($self, $product) = @_;
    return $self->{$product} < 1;
}


sub has_glut {
    my ($self, $product) = @_;
    return $self->{$product} > 100;
    
}

# Loss of product due to usage, spoilage or theft
sub shrinkage {
    my ($self) = @_;

    my @report;
    for my $product ('ore', 'energy') {
        my $shrinkage = int($self->{$product} * rand(0.5));
        next if $shrinkage < 1;
        
        $self->{$product} -= $shrinkage;
        push @report, sprintf("%d units of %s", $shrinkage, $product);
    }

    if (@report) {
        $self->msg("shrinkage loses: "
                   . color("bold white")
                   . join("; ", @report)
                   . color("reset")
                  );
    }
}


sub msg {
    my ($self, @msg) = @_;
    return unless @msg;
    
    printf("  World] %s\n", join("; ", @msg));
}


#----------------------------------
package Actor;
use Term::ANSIColor;

our $ID = 0;
sub new {
    my $class = shift;
    my %self  = @_;
    
    $self{id}     = $Actor::ID++;
    $self{caps}   = 0;
    $self{energy} = 0;
    $self{ore}    = 0;
    $self{starvation} = 0;
    bless \%self, $class;

    return \%self;
}

sub is_dead {
    my ($self) = @_;
    return ($self->{starvation} > 4);
}

sub sell {
    my ($self, $product) = @_;

    return if $self->is_dead;

    my @report;
    for my $product ('ore', 'energy') {
        # Do I need this?
        if ($self->{$product} < 10) {
            next;
        }

        my $want = int(rand($self->{$product}));
        
        next if $want < 1;

        # Compute the unit price for this product
        my $unit_price = $self->{world}->unit_price($product);

        # Pay the actor for the crop 
        $self->{caps} += $unit_price * $want; # fiat money

        # Add this crop to the world supply
        $self->{world}->{$product} += $want;
        
        # Remove this amount from Actor inventor
        $self->{$product} -= $want;

        push @report, sprintf("sells $want units of $product \@ %0.2f caps/unit", $unit_price);
    }

    $self->msg(@report);
}


sub buy {
    my ($self, $product) = @_;

    return if $self->is_dead;
    
    my @report;
    for my $product ('ore', 'energy') {
        next if $self->{world}->has_shortage($product); # can't buy

        # Do I need this?
        if ($self->{$product} > 10) {
            next;
        }

        my $want = int(rand($self->{world}->{$product}));
        next unless $want;
        
        die("ERROR: $self->{world}->{$product}") if $self->{world}->{$product} < 1;

        # Compute the unit price for this good
        my $unit_price = $self->{world}->unit_price($product);

        # Can the Actor afford to pay for it?
        my $invoice = ($unit_price * $want);
        if ($invoice <= $self->{caps}) {
            # Debit the Actor's wealth
            $self->{caps} -= $invoice;

            # Remove the amount from the world supply
            $self->{world}->{$product} -= $want;
            
            # Add the amount to the Actor's supply;
            $self->{$product} += $want;
            push @report, sprintf("buys $want units of $product \@ %0.2f caps/unit", $unit_price);
            
        } else {
            push @report, "cannot buy $want units of $product. Not enough caps";
        }
    }

    $self->msg(@report);
}


sub produce {
    my ($self) = @_;
    return if $self->is_dead;
    
    my @report;
    for my $product ('ore', 'energy') {
        my $harvest = int(rand() * 10);
        next unless $harvest;
        
        $self->{$product} += $harvest;
        $self->{starvation} -= 1 if $self->{starvation} > 0;
        
        push @report, "produced $harvest units of $product";
    }

    $self->msg(@report);
}

sub consume {
    my ($self) = @_;

    for my $product ('ore', 'energy') {
        if ($self->{$product} < 10) {
            $self->{starvation}++;
        } else {
            $self->{$product} -= 10;
        }
    }
}

sub status {
    my ($self) = @_;

    $self->msg(sprintf("ore: %3d; energy: %3d; caps: %10.2f; total: %10.2f",
                       $self->{ore},
                       $self->{energy},
                       $self->{caps},
                       $self->total_assets_in_caps
                      ));
    return;
}

sub total_assets_in_caps {
    my ($self) = @_;
    my $caps = $self->{caps};

    for my $product ('ore', 'energy') {
        my $unit_price = $self->{world}->unit_price($product, 1);
        $caps += $self->{$product} * $unit_price;
    }
    
    return $caps;
}

# Loss of product due to usage, spoilage or theft
sub shrinkage {
    my ($self) = @_;

    my @report;
    for my $product ('ore', 'energy') {
        my $shrinkage = int($self->{$product} * rand(1));
        next if $shrinkage < 1;
        
        $self->{$product} -= $shrinkage;
        push @report, sprintf("%d units of %s", $shrinkage, $product);
    }

    if (@report) {
        $self->msg("shrinkage loses: " . join("; ", @report));
    }
}

sub msg {
    my ($self, @msg) = @_;

    return unless @msg;

    my $state = "";
    if ($self->is_dead) {
        $state = color("bold white") . " {DEAD} ". color("reset");
    } elsif ($self->{starvation}) {
        $state = color("bold white") . " {STARVING} ". color("reset");
    }

    printf("Actor %d%s] %s\n", $self->{id},
           $state,
           join("; ", @msg)
          );
}

#---------------------------

package main;

Main();

sub Main {
    $|++;
    my $world = World->new();
    my @actors;
    for (0..3) {
        push @actors, Actor->new(world => $world);
    }

    my $week = 0;
    while (1) {
        printf "\n===Week %3d; %d ore; %d energy===\n\n", $week++, $world->{ore}, $world->{energy};

        for my $actor (sort_wealthy(@actors)) {
            $actor->status;
        }
        print "\n";

        last if all { $_->is_dead } @actors;
        
        for my $actor (@actors) {
            $actor->produce;
            $actor->sell;
        }
        
        for my $actor (@actors) {
            $actor->buy;
        }

        for my $actor (@actors) {
            $actor->consume;
            $actor->shrinkage;
        }

        $world->shrinkage;
        
        # sleep(1);
        # print "\nContinue? "; <>;
    }
    
    (my $winner) = sort_wealthy(@actors);
    printf "GAME OVER - Winner: Actor %d\n", $winner->{id};

}

sub sort_wealthy {
    my (@actors) = @_;

    return (
            map  { $_->[1]                            }
            sort { $b->[0] <=> $a->[0]                }
            map  { [ $_->total_assets_in_caps => $_ ] } @actors
           );
}

1;
