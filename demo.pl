# Get the gist of the game using a few dumb bots

use strict;
use warnings;
sub POE::Kernel::ASSERT_DEFAULT () { 1 };
use POE;
use POE::Component::Logger;
use Data::Dumper;

my $heap = {
            players => [],
           };

POE::Component::Logger->spawn(ConfigFile => "logger.cfg");

# Create three bots with different strategies
my $alias = 'player1';
POE::Session->create(heap => $heap, 
                              inline_states => {
                                                '_default' => sub {
                                                    my ($event, $args) = @_[ARG0, ARG1];
                                                    Logger->log(sprintf("[%d] default for event '$event'",
                                                                        $_[SESSION]->ID
                                                                       ));
                                                },
                                                'turn' => sub {
# REALLY need three stages: PRODUCTION, SELLING, BUYING
                                                    sleep 3;
                                                    Logger->log(sprintf("[%d] ends its turn",
                                                                        $_[SESSION]->ID
                                                                       ) 
                                                               );
                                                },
                                                _stop => sub { 
                                                    Logger->log("STOPPING ID: " . $_[SESSION]->ID);
                                                },
                                                _start => sub {
                                                    Logger->log(sprintf("%d session initialized", $_[SESSION]->ID));
                                                    $_[KERNEL]->alias_set($alias);
                                                }
                                               });

push @{$heap->{players}}, $alias;

$alias = 'player2';
POE::Session->create(heap => $heap, 
                              inline_states => {
                                                '_default' => sub {
                                                    my ($event, $args) = @_[ARG0, ARG1];
                                                    Logger->log(sprintf("[%d] default for event '$event'",
                                                                        $_[SESSION]->ID
                                                                       ));
                                                },
                                                'turn' => sub {
                                                    sleep 1;
                                                    Logger->log(sprintf("[%d] ends its turn",
                                                                        $_[SESSION]->ID
                                                                       ) 
                                                               );

                                                },
                                                _stop => sub { 
                                                    Logger->log("STOPPING ID: " . $_[SESSION]->ID);
                                                },
                                                _start => sub {
                                                    Logger->log(sprintf("%d session initialized", $_[SESSION]->ID));
                                                    $_[KERNEL]->alias_set($alias);
                                                }
                                               });
push @{$heap->{players}}, $alias;
# Create a dungeon master to update the world
POE::Session->create(heap => $heap,
                     inline_states => {
                                       '_default' => sub {
                                           my ($event, $args) = @_[ARG0, ARG1];
                                           Logger->log(sprintf("[%d] default for event '$event'",
                                                               $_[SESSION]->ID
                                                              ));
                                       },
                                       
                                       'run_players' => sub {
                                           my ($heap) = ($_[HEAP]);
                                           # Logger->log(Dumper(\@_));

                                           for my $player_id (@{$heap->{players}}) {
                                               Logger->log("KERNEL: turn for $player_id");
                                               $_[KERNEL]->post($player_id, "turn");
                                           }
                                       },
                                       
                                       'maint' => sub {
                                           Logger->log("KERNEL: Maint");
                                           $_[KERNEL]->yield("run_players");
                                           
                                           $_[KERNEL]->delay("maint" => 1);
                                           
                                       },
                                       _start => sub {
                                           Logger->log("KERNEL: ID is " . $_[SESSION]->ID);
                                           $_[KERNEL]->yield("maint");
                                       }
                                      });

print "Starting\n";
POE::Kernel->run();

exit;
