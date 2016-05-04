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
    $self{energy} = 100;
    $self{ore}    = 100;
    $self{week}   = 1;
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
        #
        #push @report,
        #    color("bold white")
        #  . "World glut of $product: $supply units available"
        #  . color("reset");

        $supply = $over_abundance - $fudge;
    }

    if ($supply < 0) {
        $supply = 0;
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
    my $banner = '=' x 7;

    printf(
        "%sWeek %d: Ore[%4d]: %2.2f caps/unit; Energy[%4d]: %2.2f caps/unit%s\n\n",
        $banner, $self->{week}, $self->{ore}, $self->unit_price("ore"),
        $self->{energy}, $self->unit_price("energy"), $banner,
    );
} # end sub status

#----------------------------------
package Commodity;

sub new {
    my ($class) = shift;
    my %args = (
        product           => undef, # ore|energy
        generator_name    => undef,
        harvest           => 0,
        buy_cost          => 0,
        maint_cost_amount => 0,
        maint_cost_type   => 0,     # ore|energy|caps
        tax               => 0,
        @_
    );

    my %self = (_attr => \%args);
    my $self = bless(\%self, (ref $class || $class));
    $self->_init_accessors();

    return $self;
} # end sub new

sub _init_accessors {
    my ($self) = @_;
    my $class  = ref $self;
    my $attrs  = $self->{_attr};

    for my $key (keys %$attrs) {
        my $existing;
        eval "\$existing = *${class}::${key}{CODE}";
        next if $existing;

        # monkey patch the accessors into the class
        my $method =
          "sub $class::$key { my (\$s, \$v) = \@_; (defined \$v) && (\$s->{_attr}->{$key} = \$v); \$s->{_attr}->{$key} }";
        eval $method;

        die "Creating $class::${key} - $@\n---\n$method\n---\n" if $@;
    }
} # end sub _init_accessors


#----------------------------------
package Ore;
our @ISA = ('Commodity');
sub new {
    my ($class) = shift;
    my %args = (
        product           => "ore",
        generator_name    => "ore mine",
        harvest           => 15,
        buy_cost          => 20,
        maint_cost_amount => 5,
        maint_cost_type   => "energy",
        tax               => 8,
        @_
    );
    return $class->SUPER::new(%args);
} # end sub new


#----------------------------------
package Energy;
our @ISA = ('Commodity');
sub new {
    my ($class) = shift;
    my %args = (
        product           => "energy",
        generator_name    => "wind farm",
        harvest           => 30,
        buy_cost          => 60,
        maint_cost_amount => 10,
        maint_cost_type   => "ore",
        tax               => 15,
        @_
    );
    return $class->SUPER::new(%args);
} # end sub new


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
    $self{generators} = { ore => [], energy => [] };

    bless \%self, $class;

    return \%self;
} # end sub new


sub is_dead {
    my ($self) = @_;
    return ($self->{starvation} > 8);
} # end sub is_dead


sub sell {
    my ($self, $product) = @_;

    return if $self->is_dead;

    my @report;
    for my $product ('ore', 'energy') {

        # Do not sell if you are not starving
        next if $self->{starvation} == 0;

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

        # Am I starving?  Do I need this?
        if ($self->{starvation} < 3) {
            next;
        }

        # Am I broke?
        next unless $self->{caps};

        my $supply     = $self->{world}->{$product};
        my $unit_price = $self->{world}->unit_price($product);

        # I WANT ALL THE THINGS!
        my $want = int($self->{caps} / $unit_price);
        next unless $want;

        if ($want > $supply) {
            $want = $supply;
        }

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
    return if $self->is_dead;

    my @report;
    my @products = shuffle('ore', 'energy');

    # TODO: make smarter decisions about what and when to buy
    for my $product (@products) {

        # If starving, do not take on more liabilities, maybe?
        #        if ($self->{starvation} > 4) {
        #            next;
        #        }

        if (my $commodity = $self->build_generator($product)) {
            push @report,
              sprintf(
                "built another %s (%d total)",
                $commodity->generator_name,
                scalar @{ $self->{generators}->{$product} }
              );
        }
    }

    $self->msg(@report);
} # end sub build


sub build_generator {
    my ($self, $product) = @_;
    return if $self->is_dead;

    my $commodity;

    # Sure looks like a Factory method...
    if ($product eq 'ore') {
        $commodity = Ore->new;
    } elsif ($product eq 'energy') {
        $commodity = Energy->new;
    } else {
        die "Unknown product '$product'";
    }

    # Afford this generator?
    return unless $self->{caps} >= $commodity->buy_cost;

    # Pay for it
    $self->{caps} -= $commodity->buy_cost;

    # Add generator
    push @{ $self->{generators}->{$product} }, $commodity;

    return $commodity;
} # end sub build_generator


sub produce {
    my ($self) = @_;
    return if $self->is_dead;

    my @report;
    for my $product ('ore', 'energy') {
        # For each kind of generator, see what is produced
        my $harvest = 0;

        for my $commodity (@{ $self->{generators}->{$product} }) {
            $harvest = int(rand() * $commodity->harvest);
            next unless $harvest;

            $self->{$product} += $harvest;
        }

        push @report, "produced $harvest units of $product" if $harvest;
    }

    $self->msg(@report);
} # end sub produce


sub consume {
    my ($self) = @_;

    return if $self->is_dead;

    # Consumption to be based on # of generators
    my @report;
    for my $product ('ore', 'energy') {
        my @consumption = ();

        for my $commodity (@{ $self->{generators}->{$product} }) {
            $consumption[0] = $commodity->generator_name;
            $consumption[2] = $commodity->maint_cost_type;

            #<<<
            # Do I have enough $product to feed this generator?
            if ($self->{ $commodity->maint_cost_type } < $commodity->maint_cost_amount) {
                $self->{starvation}++;
            } else {
                $self->{starvation}-- if $self->{starvation} > 0;
            }

            my $cost = $commodity->maint_cost_amount;

            # Fleeced the actor of what you can
            if ($cost > $self->{ $commodity->maint_cost_type }) {
                $cost = $self->{ $commodity->maint_cost_type };
            }

            $self->{ $commodity->maint_cost_type } -= $cost;
            $consumption[1] += $cost;
            
            #>>>
        }

        if ($consumption[1]) {
            my $amt = scalar @{ $self->{generators}->{$product} };
            push @report,
              sprintf(
                "%d %s%s consumed %d units of %s",
                $amt, $consumption[0], ($amt > 1 ? "s" : ""),
                $consumption[1], $consumption[2]
              );
        }
    }

    $self->msg(@report);
} # end sub consume


sub tax {
    my ($self) = @_;

    # Should be a penalty for not paying taxes
    my @report;
    for my $product ('ore', 'energy') {
        my $total_cost = 0;
        for my $commodity (@{ $self->{generators}->{$product} }) {
            my $cost =
              $commodity->tax > $self->{caps} ? $self->{caps} : $commodity->tax;
            $self->{caps} -= $cost;
            $total_cost += $cost;
        }

        push @report,
          sprintf("paid %d caps in taxes for %s production",
            $total_cost, $product);
    }

    $self->msg(@report);
} # end sub tax


sub status {
    my ($self) = @_;

    $self->msg(
        sprintf(
            "ORE mines: %2d; reserves %2d; maint: %d of %s; ENERGY farms: %2d; reserves: %2d; maint: %d of %s; CAPS: %5.2f; TOTAL: %6.2f",
            scalar @{ $self->{generators}->{ore} },
            $self->{ore},
            $self->maintenance_cost("ore"),
            scalar @{ $self->{generators}->{energy} },
            $self->{energy},
            $self->maintenance_cost("energy"),
            $self->{caps},
            $self->total_assets_in_caps
        )
    );
    return;
} # end sub status

sub maintenance_cost {
    my ($self, $product) = @_;

    my $commodity;
    if ($product eq 'ore') {
        $commodity = Ore->new;
    } elsif ($product eq 'energy') {
        $commodity = Energy->new;
    } else {
        die "Unknown product '$product'";
    }

    my $producers = @{ $self->{generators}->{$product} };
    return ($producers * $commodity->maint_cost_amount,
        $commodity->maint_cost_type);
} # end sub maintenance_cost


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
    return if $self->is_dead;

    my @report;
    for my $product ('ore', 'energy') {
        my $shrinkage = int($self->{$product} * rand(0.25));
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
        $state =
            color("bold white")
          . "{STARVING-$self->{starvation}}"
          . color("reset");
    }

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

        print "***Start of Week***\n";
        for my $actor (sort_wealthy(@actors)) {
            $actor->status;
        }
        print "\n***Activity***\n";

        for my $actor (@actors) {
            $actor->build;
        }

        print "---\n";
        for my $actor (@actors) {
            $actor->produce;
            $actor->sell;
        }

        print "---\n";
        for my $actor (@actors) {
            $actor->buy;
        }

        print "---\n";
        for my $actor (@actors) {
            $actor->consume;
            $actor->shrinkage;
            $actor->tax;
        }

        $world->shrinkage;

        print "\n***End of Week***\n";
        for my $actor (sort_wealthy(@actors)) {
            $actor->status;
        }

        last if all { $_->is_dead } @actors;

        # sleep(1);
        # last unless abort();

    }

    (my $winner) = sort_wealthy(@actors);
    printf "GAME OVER - Winner: Actor %d in week %d\n", $winner->{id}, $week;

} # end sub Main

sub sort_wealthy {
    my (@actors) = @_;

    return (
        map  { $_->[1] }
        sort { $b->[0] <=> $a->[0] }
        map  { [ $_->total_assets_in_caps => $_ ] } @actors
    );
} # end sub sort_wealthy

sub abort {
    print "\nContinue? ";
    my $ans = <>;
    return if $ans =~ /q/i;
    return 1;
} # end sub abort

1;
