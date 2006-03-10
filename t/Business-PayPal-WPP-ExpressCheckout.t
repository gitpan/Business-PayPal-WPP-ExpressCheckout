use Test::More tests => 6;
BEGIN { use_ok('Business::PayPal::WPP::ExpressCheckout') };

#########################

=pod

The tester must supply their own PayPal sandbox seller authentication
(either using certificates or 3-token auth), as well as the buyer
sandbox account (email address).

Should we set env variables, prompt for them, or have them in a conf
file? Prompt for them, but we should allow for an input file as an env
variable:

  WPP_TEST=auth.txt make test

=cut

unless( $ENV{WPP_TEST} && -f $ENV{WPP_TEST} ) {

    ## prompt for information
    print STDERR <<"_TESTS_";

Please supply a filename that contains your authentication information
(to avoid this prompt in the future, you may supply a file containing
the tokens with the WPP_TEST environment variable.

E.g., Use "WPP_TEST=my_auth.txt make test" (for Bourne shell derivates) or
"setenv WPP_TEST my_auth.txt && make test" (for C-shell derivates).

See 'auth.sample.*' files in this package for an example of the file
format. Variables are case-*sensitive*.

_TESTS_

    print STDERR "Authentication information filename: ";
    $ENV{WPP_TEST} = <STDIN>; chomp $ENV{WPP_TEST};
}

my %args = ();

open FILE, "<", $ENV{WPP_TEST}
  or die "Could not open $ENV{WPP_TEST}: $!\n";

my @variables = qw( Username Password Signature Subject
		    CertFile CertPass CertBoth
		    BuyerEmail
		  );

my %patterns = ();
@patterns{map { qr/^$_\b/i } @variables} = @variables;

while( <FILE> ) {
  chomp;

 MATCH: for my $pat (keys %patterns) {
    next unless $_ =~ $pat;
    (my $value = $_) =~ s/$pat\s*=\s*(.+)/$1/;
    $args{ $patterns{$pat} } = $value;
    delete $patterns{$pat};
    last MATCH;
  }
}

close FILE;

## leave this!
$args{sandbox} = 1;

## we're passing more to new() than we normally would because we're
## using %args elsewhere below. See documentation for the correct
## arguments.
my $pp = new Business::PayPal::WPP::ExpressCheckout( %args );

##
## set checkout info
##
#$Business::PayPal::WPP::ExpressCheckout::Debug = 1;
my $token = $pp->SetExpressCheckout
  ( OrderTotal => '55.43',
    ReturnURL  => 'http://site.tld/return.html',
    CancelURL  => 'http://site.tld/canceltation.html', 
    Custom     => "This field is custom. Isn't that great?",
    PaymentAction => 'Sale',
    BuyerEmail => $args{BuyerEmail},   ## from %args
  );
#$Business::PayPal::WPP::ExpressCheckout::Debug = 0;

ok( $token, "Got token" );

die "No token from PayPal! Check your authentication information and try again." unless $token;

my $pp_url = "https://www.sandbox.paypal.com/cgi-bin/webscr?cmd=_express-checkout&token=$token";

print STDERR <<"_TOKEN_";

Now paste the following URL into your browser (you'll need to have
another browser window already logged into the PayPal developer site):

  $pp_url

Login to PayPal as the Buyer you specified in '$ENV{WPP_TEST}' and
proceed to checkout (this authorizes the transaction represented by
the token). When finished, PayPal will redirect you to a non-existent
URL:

  http://site.tld/return.html?token=$token&PayerID=XXXXXXXXXXXXX

Notice the *PayerID* URL argument (XXXXXXXXXXXXX) on the redirect from
PayPal.
_TOKEN_

print STDERR "\nType or paste that PayerID here and hit Enter: \n";

my $payerid = <STDIN>; chomp $payerid;

die "Need a PayerID.\n" unless $payerid;

##
## get checkout details
##
my %details = $pp->GetExpressCheckoutDetails($token);
is( $details{Token}, $token, "details ok" );

#use Data::Dumper;
#print STDERR Dumper \%details;

$details{PayerID} = $payerid;

my %payment = ( Token          => $details{Token},
		PaymentAction  => 'Sale',
		PayerID        => $details{PayerID},
		OrderTotal     => '55.43',
	      );

##
## do checkout
##
my %payinfo = $pp->DoExpressCheckoutPayment(%payment);

is( $payinfo{Ack}, 'Success', "successful payment" );
is( $payinfo{Token}, $token, "payment ok" );
is( $payinfo{GrossAmount}, 55.43, "amount correct" );
