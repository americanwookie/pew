#!/usr/local/bin/perl

use strict;
use Net::IMAP::Simple::SSL ();
use Email::Simple          ();
use Util                   ();

#Settings
my $config = Util::load_config();

# Create the object
my $imap = Net::IMAP::Simple::SSL->new( $config->{'server'}->{'imap_server'} ) ||
  die "Unable to connect to IMAP: $Net::IMAP::Simple::errstr\n";

if(!$imap->login( $config->{'server'}->{'user'}, $config->{'server'}->{'pass'} )){
  print STDERR "Login failed: " . $imap->errstr . "\n";
  exit(64);
}

my %mailboxes = map { $_ => 1 } $imap->mailboxes();
die($config->{'server'}->{'main_folder'}.' isn\'t a mailbox') if( !exists( $mailboxes{$config->{'server'}->{'main_folder'}} ) );

my $nm = $imap->select( $config->{'server'}->{'main_folder'} );
print "Looking at $nm messages\n";
for(my $i = 1; $i <= $nm; $i++){
  print "On $i\n" unless( $i % 1000);

  my $es = Email::Simple->new(join '', @{ $imap->top($i) } );
  foreach my $filter ( @{$config->{'filters'}} ) {
    my $do;
    my $boolean = $filter->{'boolean'} || 'AND';
    if( $boolean eq 'AND' ) {
      $do = 1;
    } elsif( $boolean eq 'OR' ) {
      $do = 0;
    } else {
      warn "Unknown boolean logic $i for filter named $filter->{'name'}";
      next;
    }
    if( !@{ $filter->{'rules'} } ) {
      warn "No rules for filter named $filter->{'name'}";
      next;
    }
    if( $filter->{'action'} ne 'move' ) {
      warn "No such action $filter->{'action'} for filter named $filter->{'name'}";
      next;
    }
    if( !exists( $mailboxes{$filter->{'destination'}} ) ) {
      warn "Destination mailbox $filter->{'destination'} doesn't exist for filter named $filter->{'name'}";
      next;
    }

    if(   $es->header('Subject') eq 'Test'
       && $es->header('From') =~ /americanwookie/ ) {
      print "i'm here\n";
    }

    foreach my $rule ( @{ $filter->{'rules'} } )  {
      if(   (   ref($rule->{'value'}) eq 'Regexp'
             && $es->header( $rule->{'header'} ) =~ $rule->{'value'} )
         || (   !ref($rule->{'value'})
             && $es->header( $rule->{'header'} ) eq $rule->{'value'} ) ) {
        if( $boolean eq 'OR' ) {
          $do = 1;
          last;
        }
      } else {
        if( $boolean eq 'AND' ) {
          $do = 0;
          last;
        }
      }
    }

    if( $do ) {
      $filter->{'matching'} ||= [];
      push( @{$filter->{'matching'}}, $i );
      #if( $filter->{'action'} eq 'move' ) {
      #  $imap->copy( $i, $filter->{'destination'} ) && $imap->delete( $i ) && print "Moved and deleted $i well\n";
      #}
      last;
    }
  }
}
foreach my $filter ( @{$config->{'filters'}} ) {
  $filter->{'matching'} ||= [];
  while( @{$filter->{'matching'}} ) {
    my @sub = @{$filter->{'matching'}};
#TODO: Make messages per run configuratble
#    if( scalar @{$filter->{'matching'}} > 1000 ) {
#      @sub = @{$filter->{'matching'}}[0..999];
#      $filter->{'matching'} = [ @{$filter->{'matching'}}[1000..$#{$filter->{'matching'}}] ];
#    } else {
      $filter->{'matching'} = [];
#    }
    my $list = Util::list2range( @sub );
    if( $imap->copy( $list, $filter->{'destination'} ) ) {
      if( $imap->delete( $list ) ) {
        print "Moved and deleted ".scalar @sub." messages for $filter->{'name'}\n";
      } else {
        die "Error ".$imap->errstr." encountered when deleting for $filter->{'name'}";
      }
    } else {
      die "Error ".$imap->errstr." encountered when copying for $filter->{'name'}\n";
    }
  }
}
$imap->expunge_mailbox( $config->{'server'}->{'main_folder'} );
