# Get the gist of the game using a few dumb bots
use strict;
use warnings;
use Time::HiRes;
use Data::Dumper;
use List::Util ('all', 'shuffle');

#--------------------------------
package World;
use Term::ANSIColor;

sub new {
    my $class = shift;
    my %self  = @_;

    # $self{caps}   = 100;
    $self{energy}   = 100;
    $self{ore}      = 100;
    $self{week}     = 1;
    bless \%self, $class;
    \%self;
} # end sub new

sub fn {
    my ($self, $x) = @_;
    $x *= 1.0;
    return ($x**2.0) - (4.0 * $x) + 4.0;
} # end sub fn

sub unit_price {
    my ($self, $product, $quite_mode) = @_;
    $quite_mode ||= 0;

    my @report;

    my $supply = $self->{$product};
    # Map the supply into the domain of the demand curve (200 units)

    my $over_abundance = 200.0;
    my $base_cost      = 10.0;

    # would "tuning parameter" sound smarter?
    # We want the unit price of a flooded market to be about 1 cap
    # $fudge gets us there
    my $fudge = 35;
    if ($supply > ($over_abundance - $fudge)) {
        push @report,
            color("bold white")
          . "World glut of $product: $supply units available"
          . color("reset");

        $supply = $over_abundance - $fudge;
    }

    if ($supply < 0) {
        $supply = 0;
    }

    if ($supply < 1.0) {
        push @report,
          color("bold white")
          . sprintf("World shortage of $product: %0.2f units available",
            $supply)
          . color("reset");
    }

    # Range of X values 0 - 2
    my $scalar = $self->fn(2.0 * ($supply / $over_abundance));

    $self->msg(@report) unless $quite_mode;

    return $scalar * $base_cost;
} # end sub unit_price

sub has_shortage {
    my ($self, $product) = @_;
    return $self->{$product} < 1;
} # end sub has_shortage


sub has_glut {
    my ($self, $product) = @_;
    return $self->{$product} > 100;

} # end sub has_glut

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
              . color("reset"));
    }
} # end sub shrinkage


sub msg {
    my ($self, @msg) = @_;
    return unless @msg;

    printf("  World] %s\n", join("; ", @msg));
} # end sub msg

sub status {
    my ($self) = @_;
    my $banner = '='x7;

    printf(
      "%sWeek %d: Ore[%4d]: %2.2f caps/unit; Energy[%4d]: %2.2f caps/unit%s\n\n",
      $banner,
      $self->{week},
      $self->{ore},
      $self->unit_price("ore"),
      $self->{energy},
      $self->unit_price("energy"),
      $banner,
      );
} # end sub status

#----------------------------------
package Actor;
use Term::ANSIColor;
use List::Util ('all', 'shuffle');

our $ID = 0;
sub new {
    my $class = shift;
    my %self  = @_;

    $self{id}         = $Actor::ID++;
    $self{caps}       = 100;
    $self{energy}     = 0;
    $self{ore}        = 0;
    $self{starvation} = 0;
    $self{generators} = { ore => 0, energy => 0 };
    $self{consumption} = { ore => { product => "energy", cost => 10 },
                           energy => { product => "ore", cost => 5 },
                         };

    bless \%self, $class;

    return \%self;
} # end sub new

sub is_dead {
    my ($self) = @_;
    return ($self->{starvation} > 4);
} # end sub is_dead

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

        push @report,
          sprintf("sells $want units of $product \@ %0.2f caps/unit",
            $unit_price);
    }

    $self->msg(@report);
} # end sub sell


sub buy {
    my ($self, $product) = @_;

    return if $self->is_dead;

    my @report;
    for my $product ('ore', 'energy') {
        next if $self->{world}->has_shortage($product); # can't buy

        # Am I starving?  Do I need this?
        if ($self->{starvation} < 4) {
            next;
        }

        my $want = int(rand($self->{world}->{$product}));
        next unless $want;

        die("ERROR: $self->{world}->{$product}")
          if $self->{world}->{$product} < 1;

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
            push @report,
              sprintf("buys $want units of $product \@ %0.2f caps/unit",
                $unit_price);

        } else {
            push @report, "cannot buy $want units of $product. Not enough caps";
        }
    }

    $self->msg(@report);
} # end sub buy


sub build {
    my ($self) = @_;

    my %names = (
        "ore"    => "ore mine",
        "energy" => "wind farm",
    );

    my @report;
    my @products = shuffle('ore', 'energy');

    # TODO: make smarter decisions about what and when to buy
    for my $product (@products) {

        # If starving, do not take on more liabilities
        if ($self->{starvation} > 4) {
            next;
        }
        if ($self->build_generator($product)) {
            push @report,
              sprintf("built another %s (%d total)",
                $names{$product}, $self->{generators}->{$product});
        }
    }

    $self->msg(@report);
} # end sub build


sub build_generator {
    my ($self, $product) = @_;

    my %costs = (
        "ore"    => 20,
        "energy" => 100
    );

    # Afford this generator?
    return unless $self->{caps} >= $costs{$product};

    # Pay for it
    $self->{caps} -= $costs{$product};

    # Add generator
    $self->{generators}->{$product} += 1;
} # end sub build_generator


sub produce {
    my ($self) = @_;
    return if $self->is_dead;

    my %capacities = (
        "ore"    => 50,
        "energy" => 50
    );

    my @report;
    for my $product ('ore', 'energy') {
        # For each kind of generator, see what is produced
        my $harvest = 0;
        for (my $i = 0; $i < $self->{generators}->{$product}; $i++) {
            $harvest = int(rand() * $capacities{$product});
            next unless $harvest;

            $self->{$product} += $harvest;

            # Thing again about the starvation rules
            $self->{starvation} -= 1 if $self->{starvation} > 0;
        }

        push @report, "produced $harvest units of $product";
    }

    $self->msg(@report);
} # end sub produce


sub consume {
    my ($self) = @_;

    # Consumption to be based on # of generators
    for my $product ('ore', 'energy') {
        for (my $i = 0; $i < $self->{generators}->{$product}; $i++) {
            my $cost_struct = $self->{consumption}->{$product};

            # Do I have enough $product to feed this generator?
            if ($self->{ $cost_struct->{product} } < $cost_struct->{cost}) {
                $self->{starvation}++;
            } else {
                $self->{ $cost_struct->{product} } -= $cost_struct->{cost};
            }
        }
    }
} # end sub consume


sub status {
    my ($self) = @_;

    $self->msg(
        sprintf(
            "ore[%2d]: %3d; energy[%2d]: %3d; caps: %10.2f; total: %10.2f",
            $self->{generators}->{ore},    $self->{ore},
            $self->{generators}->{energy}, $self->{energy},
            $self->{caps},                 $self->total_assets_in_caps
        )
    );
    return;
} # end sub status


sub total_assets_in_caps {
    my ($self) = @_;
    my $caps = $self->{caps};

    for my $product ('ore', 'energy') {
        my $unit_price = $self->{world}->unit_price($product, 1);
        $caps += $self->{$product} * $unit_price;
    }

    return $caps;
} # end sub total_assets_in_caps


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
} # end sub shrinkage

sub msg {
    my ($self, @msg) = @_;

    return unless @msg;

    my $state = "";
    if ($self->is_dead) {
        $state = color("bold red") . "{DEAD}" . color("reset");
    } elsif ($self->{starvation}) {
        $state = color("bold white") . "{STARVING}" . color("reset");
    }

    # Add padding
    my $padding = 25 - length($state);
    $state = (' ' x $padding) . $state;

    printf("%s Actor %d] %s\n", $state, $self->{id}, join("; ", @msg));
} # end sub msg

#---------------------------

package main;

Main();

sub Main {
    $|++;
    my $world = World->new();
    my @actors;
    for (0 .. 3) {
        push @actors, Actor->new(world => $world);
    }

    my $week = 0;
    while (1) {
        $world->{week} = $week++;
        $world->status;

        for my $actor (sort_wealthy(@actors)) {
            $actor->status;
        }
        print "\n";

        last if all { $_->is_dead } @actors;

        for my $actor (@actors) {
            $actor->build;
        }

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
        print "\nContinue? ";
        my $ans = <>;
        last if $ans =~ /q/i;
    }

    (my $winner) = sort_wealthy(@actors);
    printf "GAME OVER - Winner: Actor %d\n", $winner->{id};

} # end sub Main

sub sort_wealthy {
    my (@actors) = @_;

    return (
        map  { $_->[1] }
        sort { $b->[0] <=> $a->[0] }
        map  { [ $_->total_assets_in_caps => $_ ] } @actors
    );
} # end sub sort_wealthy

1;
