package Business::PayPal::WPP::ExpressCheckout;

use 5.008001;
use strict;
use warnings;

use SOAP::Lite 0.67;

our $VERSION = '0.05';
our $CVS_VERSION = '$Id: ExpressCheckout.pm,v 1.9 2006/03/09 23:55:13 scott Exp $';
our $Debug   = 0;

## NOTE: This package exists only until I can figure out how to use
## NOTE: SOAP::Lite's WSDL support for complex types and importing
## NOTE: type definitions, at which point this module will become much
## NOTE: smaller (or non-existent).

sub C_api_sandbox () { 'https://api.sandbox.paypal.com/2.0/' }
sub C_api_live    () { 'https://api.paypal.com/2.0/' }
sub C_xmlns_pp    () { 'urn:ebay:api:PayPalAPI' }
sub C_xmlns_ebay  () { 'urn:ebay:apis:eBLBaseComponents' }
sub C_version     () { '1.0' }

## this is an inside-out object. Make sure you 'delete' additional
## members in DESTROY() as you add them.
my %Soap;
my %Header;
my %CertFile;    ## path to certificate file (pkc12)
my %CertPass;    ## password for certificate file (pkc12)
my %CertBoth;    ## combined public/private key PEM format

sub new {
    my $class = shift;
    my %args = @_;
    my $self = bless \(my $fake), $class;

    ## if you add new args, be sure to update the test file's @variables array
    $args{Username}  ||= '';
    $args{Password}  ||= '';
    $args{Signature} ||= '';
    $args{Subject}   ||= '';
    $args{sandbox} = 1 unless exists $args{sandbox};

    $CertFile{$self}  = $args{CertFile} || '';
    $CertPass{$self}  = $args{CertPass} || '';
    $CertBoth{$self}  = $args{CertBoth} || '';

    if( $args{sandbox} ) {
	$Soap{$self} = SOAP::Lite
	    ->proxy( C_api_sandbox )
	    ->uri( C_xmlns_pp );
    }

    else {
	$Soap{$self} = SOAP::Lite
	    ->proxy( C_api_live )
	    ->uri( C_xmlns_pp );
    }

    $Header{$self} = SOAP::Header
      ->name( RequesterCredentials => \SOAP::Header->value
	      ( SOAP::Data->name( Credentials => \SOAP::Data->value
				  ( SOAP::Data->name( Username  => $args{Username} )->type(''),
				    SOAP::Data->name( Password  => $args{Password} )->type(''),
				    SOAP::Data->name( Signature => $args{Signature} )->type(''),
				    SOAP::Data->name( Subject   => $args{Subject} )->type(''),
				  ),
				)->attr( {xmlns => C_xmlns_ebay} )
	      )
	    )->attr( {xmlns => C_xmlns_pp} )->mustUnderstand(1);

    return $self;
}

sub DESTROY {
    my $self = $_[0];

    delete $Soap{$self};
    delete $Header{$self};
    delete $CertFile{$self};
    delete $CertPass{$self};
    delete $CertBoth{$self};

    my $super = $self->can("SUPER::DESTROY");
    goto &$super if $super;
}


## if you specify an InvoiceID, PayPal seems to remember it and not
## allow you to bill twice with it.
sub SetExpressCheckout {
    my $self = shift;
    my %args = @_;
    my $token = '';

    my %types = ( Token                     => 'ebl:ExpressCheckoutTokenType',
		  OrderTotal                => 'cc:BasicAmountType',
		  currencyID                => '',
		  MaxAmount                 => 'cc:BasicAmountType',
		  OrderDescription          => 'xs:string',
		  Custom                    => 'xs:string',
		  InvoiceID                 => 'xs:string',
		  ReturnURL                 => 'xs:string',
		  CancelURL                 => 'xs:string',
		  Address                   => 'ebl:AddressType',
		  ReqConfirmShipping        => 'xs:string',
		  NoShipping                => 'xs:string',
		  AddressOverride           => 'xs:string',
		  LocaleCode                => 'xs:string',
		  PageStyle                 => 'xs:string',
		  'cpp-header-image'        => 'xs:string',
		  'cpp-header-border-color' => 'xs:string',
		  'cpp-header-back-color'   => 'xs:string',
		  'cpp-payflow-color'       => 'xs:string',
		  PaymentAction             => '',
		  BuyerEmail                => 'ebl:EmailAddressType' );

    ## set some defaults
    $args{PaymentAction} ||= 'Sale';
    $args{currencyID}    ||= 'USD';

    ## SetExpressCheckoutRequestDetails
    my @secrd = 
      ( SOAP::Data->name( OrderTotal => delete $args{OrderTotal} )->type( $types{OrderTotal} )
	->attr( {currencyID => delete $args{currencyID}, xmlns => C_xmlns_ebay}),
	SOAP::Data->name( ReturnURL => delete $args{ReturnURL} )->type( $types{ReturnURL} ),
	SOAP::Data->name( CancelURL => delete $args{CancelURL} )->type( $types{CancelURL} ),
      );

    ## add all the other fields
    for my $field ( keys %types ) {
	next unless $args{$field};
	push @secrd, SOAP::Data->name( $field => $args{$field} )->type( $types{$field} );
    }

    my $request = SOAP::Data
      ->name( SetExpressCheckoutRequest => \SOAP::Data->value
	      ( SOAP::Data->name( Version => C_version )
		->type('string')->attr( {xmlns => C_xmlns_ebay} ),
		SOAP::Data->name( SetExpressCheckoutRequestDetails => \SOAP::Data->value(@secrd) )
		->attr( {xmlns => C_xmlns_ebay} ),
	      )
	    )->type( 'ns:SetExpressCheckoutRequestType' );

    my $method = SOAP::Data->name( 'SetExpressCheckoutReq' )->attr( {xmlns => C_xmlns_pp} );

    my $som = $self->_doCall( $method => $request );

    if( $som->fault ) {
	warn "FAULT: " . $som->faultdetail . "\n";
	return;
    }

    if( my $token = $som->valueof('/Envelope/Body/SetExpressCheckoutResponse/Token') ) {
	return $token;
    }

    warn <<_BADNESS_;
No token, no fault in SetExpressCheckout! Try setting \$Debug = 1 and
look at the SOAP data we send and receive.
_BADNESS_

    return;
}


sub GetExpressCheckoutDetails {
    my $self = shift;
    my $token = shift;

    my $request = SOAP::Data
      ->name( GetExpressCheckoutDetailsRequest => \SOAP::Data->value
	      ( SOAP::Data->name( Version => C_version )
		->type('string')->attr( {xmlns => C_xmlns_ebay} ),
		SOAP::Data->name( Token => $token )
		->type('xs:string')->attr( {xmlns => C_xmlns_ebay} ), 
	      )
	    )->type( 'ns:GetExpressCheckoutRequestType' );

    my $method = SOAP::Data->name( 'GetExpressCheckoutDetailsReq' )->attr( {xmlns => C_xmlns_pp } );

    my $som = $self->_doCall( $method => $request );

    if( $som->fault ) {
	warn "FAULT: " . $som->faultdetail . "\n";
	return;
    }

    my $path = '/Envelope/Body/GetExpressCheckoutDetailsResponse';

    my %details = ();
    $details{Ack} = $som->valueof("$path/Ack") || '';

    my @errors = ();
    unless( $details{Ack} =~ /^[Ss]uccess$/ ) {
      $details{Errors} = [ ];
      for my $enode ( $som->valueof("$path/Errors") ) {
	push @{$details{Errors}}, { LongMessage => $enode->{LongMessage},
				    ErrorCode   => $enode->{ErrorCode}, };
      }
      return %details;
    }

    my $detail_path = "$path/GetExpressCheckoutDetailsResponseDetails";
    my %detnames = ( Token           => 'Token',
		     Custom          => 'Custom',
		     InvoiceID       => 'InvoiceID',
		     ContactPhone    => 'ContactPhone',
		     Payer           => 'PayerInfo/Payer',
		     PayerID         => 'PayerInfo/PayerID',
		     PayerStatus     => 'PayerInfo/Status',
		     FirstName       => 'PayerInfo/PayerName/FirstName',
		     LastName        => 'PayerInfo/PayerName/LastName',
		     PayerBusiness   => 'PayerInfo/PayerBusiness',
		     Name            => 'PayerInfo/Address/Name',
		     Street1         => 'PayerInfo/Address/Street1',
		     Street2         => 'PayerInfo/Address/Street2',
		     CityName        => 'PayerInfo/Address/CityName',
		     StateOrProvince => 'PayerInfo/Address/StateOrProvice',
		     PostalCode      => 'PayerInfo/Address/PostalCode',
		     Country         => 'PayerInfo/Address/Country',
		   );

    for my $field ( keys %detnames ) {
      if( my $value = $som->valueof("$detail_path/$detnames{$field}") ) {
	$details{$field} = $value;
      }
    }

    return %details;
}

sub DoExpressCheckoutPayment {
    my $self = shift;
    my %args = @_;

    my %types = ( Token                     => 'xs:string',
		  PaymentAction             => '',                 ## NOTA BENE!
		  PayerID                   => 'ebl:UserIDType',
		  currencyID                => '',
		  );

    ## PaymentDetails
    my %pd_types = ( OrderTotal             => 'ebl:BasicAmountType',
		     OrderDescription       => 'xs:string',
		     ItemTotal              => 'ebl:BasicAmountType',
		     ShippingTotal          => 'ebl:BasicAmountType',
		     HandlingTotal          => 'ebl:BasicAmountType',
		     TaxTotal               => 'ebl:BasicAmountType',
		     Custom                 => 'xs:string',
		     InvoiceID              => 'xs:string',
		     ButtonSource           => 'xs:string',
		     NotifyURL              => 'xs:string',
		     );

    ## ShipToAddress
    my %st_types = ( ST_Name                   => 'xs:string',
		     ST_Street1                => 'xs:string',
		     ST_Street2                => 'xs:string',
		     ST_CityName               => 'xs:string',
		     ST_StateOrProvice         => 'xs:string',
		     ST_Country                => 'xs:string',
		     ST_PostalCode             => 'xs:string',
		     );

    ##PaymentDetailsItem
    my %pdi_types = ( PDI_Name                 => 'xs:string',
		      PDI_Amount               => 'ebl:BasicAmountType',
		      PDI_Number               => 'xs:string',
		      PDI_Quantity             => 'xs:string',
		      PDI_Tax                  => 'ebl:BasicAmountType',
		      );

    $args{PaymentAction} ||= 'Sale';
    $args{currencyID}    ||= 'USD';

    my @payment_details = ( );

    ## push OrderTotal here and delete it (i.e., and all others that have special attrs)
    push @payment_details, SOAP::Data->name( OrderTotal => $args{OrderTotal} )
	->type( $pd_types{OrderTotal} )
	->attr( { currencyID => $args{currencyID},
		  xmlns      => C_xmlns_ebay } );

    ## don't process it again
    delete $pd_types{OrderTotal};

    for my $field ( keys %pd_types ) {
	if( $args{$field} ) {
	  push @payment_details, 
	    SOAP::Data->name( $field => $args{$field} )
		->type( $pd_types{$field} );
	}
    }

    ##
    ## ShipToAddress
    ##
    my @ship_types = ();
    for my $field ( keys %st_types ) {
	if( $args{$field} ) {
	  (my $name = $field) =~ s/^ST_//;
	  push @ship_types,
	    SOAP::Data->name( $name => $args{$field} )
		->type( $st_types{$field} );
	}
    }

    if( scalar @ship_types ) {
	push @payment_details,
	SOAP::Data->name( ShipToAddress => \SOAP::Data->value
			  ( @ship_types )->type('ebl:AddressType')
			  ->attr( {xmlns => C_xmlns_ebay} ),
			  );
    }

    ##
    ## PaymentDetailsItem
    ##
    my @payment_details_item = ();
    for my $field ( keys %pdi_types ) {
	if( $args{$field} ) {
	  (my $name = $field) =~ s/^PDI_//;
	  push @payment_details_item,
	    SOAP::Data->name( $name => $args{$field} )
		->type( $pdi_types{$field} );
	}
    }

    if( scalar @payment_details_item ) {
	push @payment_details,
	SOAP::Data->name( PaymentDetailsItem => \SOAP::Data->value
			  ( @payment_details_item )->type('ebl:PaymentDetailsItemType')
			  ->attr( {xmlns => C_xmlns_ebay} ),
			  );
    }

    ##
    ## ExpressCheckoutPaymentDetails
    ##
    my @express_details = (
		 SOAP::Data->name( Token => $args{Token} )
		 ->type($types{Token})->attr( {xmlns => C_xmlns_ebay} ),
		 SOAP::Data->name( PaymentAction => $args{PaymentAction} )
		 ->type($types{PaymentAction})->attr( {xmlns => C_xmlns_ebay} ),
		 SOAP::Data->name( PayerID => $args{PayerID} )
		 ->type($types{PayerID})->attr( {xmlns => C_xmlns_ebay} ),
		 SOAP::Data->name( PaymentDetails => \SOAP::Data->value
				   ( @payment_details )->type('ebl:PaymentDetailsType')
				   ->attr( {xmlns => C_xmlns_ebay} ),
				   ), );

    ##
    ## the main request object
    ##
    my $request = SOAP::Data
      ->name( DoExpressCheckoutPaymentRequest => \SOAP::Data->value
	      ( SOAP::Data->name( Version => C_version )
		->type('string')->attr( {xmlns => C_xmlns_ebay} ),
		SOAP::Data->name( DoExpressCheckoutPaymentRequestDetails => \SOAP::Data->value
				  ( @express_details )->type( 'ns:DoExpressCheckoutPaymentRequestDetailsType' )
				)->attr( {xmlns => C_xmlns_ebay} ),
	      )
	    );

    my $method = SOAP::Data->name( 'DoExpressCheckoutPaymentReq' )->attr( {xmlns => C_xmlns_pp } );

    ## do the call
    my $som = $self->_doCall( $method => $request );

    if( $som->fault ) {
	warn "FAULT: " . $som->faultdetail . "\n";
	return;
    }

    my $path = '/Envelope/Body/DoExpressCheckoutPaymentResponse';

    my %payinfo = ();
    $payinfo{Ack} = $som->valueof("$path/Ack") || '';

    my @errors = ();
    unless( $payinfo{Ack} =~ /^[Ss]uccess$/ ) {
      $payinfo{Errors} = [];
      for my $enode ( $som->valueof("$path/Errors") ) {
	push @{$payinfo{Errors}}, { LongMessage => $enode->{LongMessage},
				    ErrorCode   => $enode->{ErrorCode}, };
      }
      return %payinfo;
    }

    my $detail_path = "$path/DoExpressCheckoutPaymentResponseDetails";
    my %paynames = ( Token               => 'Token',
		     TransactionID       => 'PaymentInfo/TransactionID',
		     TransactionType     => 'PaymentInfo/TransactionType',
		     PaymentType         => 'PaymentInfo/PaymentType',
		     PaymentDate         => 'PaymentInfo/PaymentDate',
		     GrossAmount         => 'PaymentInfo/GrossAmount',
		     FeeAmount           => 'PaymentInfo/FeeAmount',
		     SettleAmount        => 'PaymentInfo/SettleAmount',
		     TaxAmount           => 'PaymentInfo/TaxAmount',
		     ExchangeRate        => 'PaymentInfo/ExchangeRate',
		     PaymentStatus       => 'PaymentInfo/PaymentStatus',
		     PendingReason       => 'PaymentInfo/PendingReason',
		   );

    for my $field ( keys %paynames ) {
      if( my $value = $som->valueof("$detail_path/$paynames{$field}") ) {
	$payinfo{$field} = $value;
      }
    }

    return %payinfo;
}


sub _doCall {
    my $self = shift;
    my $method = shift;
    my $request = shift;

    my $som;
    {
	no warnings 'redefine';
	local *SOAP::Deserializer::typecast = sub {shift; return shift};
	$ENV{HTTPS_PKC12_FILE}      || (local $ENV{HTTPS_PKCS12_FILE}     = $CertFile{$self});
	$ENV{HTTPS_PKCS12_PASSWORD} || (local $ENV{HTTPS_PKCS12_PASSWORD} = $CertPass{$self});
	$ENV{HTTPS_KEY_FILE}        || (local $ENV{HTTPS_KEY_FILE}        = $CertBoth{$self});
	$ENV{HTTPS_CERT_FILE}       || (local $ENV{HTTPS_CERT_FILE}       = $CertBoth{$self});

	if( $Debug ) {
	    print STDERR SOAP::Serializer->envelope(method => $method, $Header{$self}, $request), "\n";
	}

	$Soap{$self}->readable( $Debug );
	$Soap{$self}->outputxml( $Debug );
	$som = $Soap{$self}->call( $Header{$self}, $method => $request );
    }

    if( $Debug ) {
	print STDERR $som, "\n";
	$som = SOAP::Deserializer->deserialize($som);  ## FIXME: this
                                                       ## doesn't put
                                                       ## things back
                                                       ## quite right
    }

    return $som;
}

1;
__END__

=head1 NAME

Business::PayPal::WPP::ExpressCheckout - Simplified Express Checkout API

=head1 SYNOPSIS

  use Business::PayPal::WPP::ExpressCheckout;

  ## certificate authentication
  my $pp = new Business::PayPal::WPP::ExpressCheckout
            ( Username   => 'my_api1.domain.tld',
              Password   => 'this_is_my_password',
              CertFile   => '/path/to/cert.pck12',
              CertPass   => '/path/to/certpw.pck12',
              sandbox    => 1 );

  ## PEM cert authentication
  my $pp = new Business::PayPal::WPP::ExpressCheckout
            ( Username   => 'my_api1.domain.tld',
              Password   => 'this_is_my_password',
              CertBoth   => '/path/to/cert.pem',
              sandbox    => 1 );

  ## 3-token authentication
  my $pp = new Business::PayPal::WPP::ExpressCheckout
            ( Username   => 'my_api1.domain.tld',
              Password   => 'Xdkis9k3jDFk39fj29sD9',  ## supplied by PayPal
              Signature  => 'f7d03YCpEjIF3s9Dk23F2V1C1vbYYR3ALqc7jm0UrCcYm-3ksdiDwjfSeii',  ## ditto
              sandbox    => 1 );

  my $token = $pp->SetExpressCheckout
                ( OrderTotal => '55.43',   ## defaults to USD
                  ReturnURL  => 'http://site.tld/return.html',
                  CancelURL  => 'http://site.tld/canceltation.html', );

  ... time passes, buyer validates the token with PayPal ...

  my %details = $pp->GetExpressCheckoutDetails($token);

  ## now ask PayPal to xfer the money
  my %payinfo = $pp->DoExpressCheckoutPayment( Token => $token,
                                               PaymentAction => 'Sale',
                                               PayerID => $details{PayerID},
                                               OrderTotal => '55.43' );

=head1 DESCRIPTION

B<Business::PayPal::WPP::ExpressCheckout> (hereafter B<BPWE>) aims to
make PayPal's "Website Payments Pro" (WPP) Express Checkout API as
simple as possible. With a little help from B<SOAP::Lite>, we can
whittle an ExpressCheckout transaction down to a few simple API calls.

B<BPWE> support both certificate authentication and the new 3-token
authentication.

=head2 new

Creates a new B<BPWE> object.

=over 4

=item B<Username>

Required. This is the PayPal API username, usually in the form of
'my_api1.mydomain.tld'. You can find or create your credentials by
logging into PayPal (if you want to do testing, as you should, you
should also create a developer sandbox account) and going to:

  My Account -> Profile -> API Access -> Request API Credentials

=item B<Password>

Required. If you use certificate authentication, this is the PayPal
API password you created yourself when you setup your certificate. If
you use 3-token authentication, this is the password PayPal assigned
you, along with the "API User Name" and "Signature Hash".

=item B<Subject>

Optional. This is used by PayPal to authenticate 3rd party billers
using your account. See the documents in L<SEE ALSO>.

=item B<Signature>

Required for 3-token authentication. This is the "Signature Hash" you
received when you did "Request API Credentials" in your PayPal
Business Account.

=item B<CertFile>

Required for certificate authentication if you're not using
B<CertBoth> and if you haven't already set the B<HTTPS_PCK12_FILE>
environment variable. This contains the path to your private key for
PayPal authentication. It is used to set the B<HTTPS_PCK12_FILE>
environment variable. You may set this environment variable yourself
and leave this field blank.

=item B<CertPass>

Required for certificate authentication if you're not using
B<CertBoth> and if you haven't already set the B<HTTPS_PCK12_PASSWORD>
environment variable. This contains the path to your private key for
PayPal authentication. It is used to set the B<HTTPS_PCK12_PASSWORD>
environment variable. You may set this environment variable yourself
and leave this field blank.

=item B<CertBoth>

Required for certificate authentication if you're not using
B<CertFile> and B<CertPass> and if you haven't already set the
B<HTTPS_KEY_FILE> and B<HTTPS_CERT_FILE> envirionment variables. This
contains the path to your PEM format certificate given to you from
PayPal (and accessible in the same location that your Username and
Password and/or Signature Hash are found) and is used to set the
B<HTTPS_KEY_FILE> and B<HTTPS_CERT_FILE> environment variables. You
may set these environment variables yourself and leave this field
blank.

=item B<sandbox>

Required. If set to true (default), B<BPWE> will connect to PayPal's
development sandbox, instead of PayPal's live site. *You must
explicitly set this to false (0) to access PayPal's live site*.

=back

=head2 SetExpressCheckout

Implements PayPal's WPP B<SetExpressCheckout> API call. Supported
parameters include:

  Token
  OrderTotal
  currencyID
  MaxAmount
  OrderDescription
  Custom
  InvoiceID
  ReturnURL
  CancelURL
  Address
  ReqConfirmShipping
  NoShipping
  AddressOverride
  LocaleCode
  PageStyle
  'cpp-header-image'
  'cpp-header-border-color'
  'cpp-header-back-color'
  'cpp-payflow-color'
  PaymentAction
  BuyerEmail

as described in the PayPal "Web Services API Reference" document. The
default currency setting is 'USD' if not otherwise specified.

Returns a scalar variable that represents the PayPal transaction token
("Token").

Required fields:

  OrderTotal, ReturnURL, CancelURL.

=head2 GetExpressCheckoutDetails

Implements PayPal's WPP B<SetExpressCheckout> API call. Supported
parameters include:

  Token

as described in the PayPal "Web Services API Reference" document. This
is the same token you received from B<SetExpressCheckout>.

Returns a hash with the following keys:

  Token
  Custom
  InvoiceID
  ContactPhone
  Payer
  PayerID
  PayerStatus
  FirstName
  LastName
  PayerBusiness
  Name
  Street1
  Street2
  CityName
  StateOrProvince
  PostalCode
  Country

Required fields:

  Token

=head2 DoExpressCheckoutPayment

Implements PayPal's WPP B<SetExpressCheckout> API call. Supported
parameters include:

  Token  
  PaymentAction (defaults to 'Sale' if not supplied)
  PayerID
  currencyID

  OrderTotal
  OrderDescription
  ItemTotal
  ShippingTotal  
  HandlingTotal  
  TaxTotal  
  Custom  
  InvoiceID  
  ButtonSource  
  NotifyURL  

  ST_Name  
  ST_Street1  
  ST_Street2  
  ST_CityName  
  ST_StateOrProvice  
  ST_Country  
  ST_PostalCode  

  PDI_Name  
  PDI_Amount  
  PDI_Number  
  PDI_Quantity  
  PDI_Tax  

as described in the PayPal "Web Services API Reference" document.

Returns a hash with the following keys:

  Token  
  TransactionID  
  TransactionType  
  PaymentType  
  PaymentDate  
  GrossAmount  
  FeeAmount  
  SettleAmount  
  TaxAmount  
  ExchangeRate  
  PaymentStatus  
  PendingReason  

Required fields:

  Token, PayerID, OrderTotal

=head1 DEBUGGING

You can see the raw SOAP XML sent and received by B<BPWE> by setting
it's B<$Debug> variable:

  $Business::PayPal::WPP::ExpressCheckout::Debug = 1;
  $pp->SetExpressCheckout( %args );

these will print on STDERR (so check your error_log if running inside
a web server).

Unfortunately, while doing this, it also doesn't put things back the
way they should be, so this should not be used in a production
environment to troubleshoot (until I get this fixed). Patches gladly
accepted which would let me get the correct SOM object back after
serialization.

Summary: until this bug is fixed, don't use B<$Debug> except in a
sandbox.

=head2 EXPORT

None by default.

=head1 CAVEATS

Because I haven't figured out how to make SOAP::Lite read the WSDL
definitions directly and simply implement those (help, anyone?), I
have essentially recreated all of those WSDL structures internally in
this module.

If PayPal changes their API (adds, removes, or changes parameters),
this module *may stop working*. I do not know if PayPal will preserve
backward compatibility. That said, you can help me keep this module
up-to-date if you notice such an event occuring.

While this module was written, PayPal added 3-token authentication,
which while being trivial to support and get working, is a good
example of how quickly non-WSDL SOAP can get behind.

Also, I didn't implement a big fat class hierarchy to make this module
"academically" correct. You'll notice that I fudged two colliding
parameter names in B<DoExpressCheckoutPayment> as a result. The good
news is that this was written quickly, works, and is dead-simple to
use. The bad news is that this sort of collision might occur again as
more and more data is sent in the API (call it 'eBay API bloat'). I'm
willing to take the risk this will be rare (PayPal--please make it
rare!).

=head1 SEE ALSO

L<SOAP::Lite>, L<https://www.paypal.com/IntegrationCenter/ic_pro_home.html>,
L<https://www.paypal.com/IntegrationCenter/ic_expresscheckout.html>,
L<https://developer.paypal.com/en_US/pdf/PP_APIReference.pdf>

=head1 AUTHOR

Scott Wiersdorf, E<lt>scott@perlcode.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Scott Wiersdorf

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.6 or,
at your option, any later version of Perl 5 you may have available.

=cut
