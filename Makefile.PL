use 5.008001;
use ExtUtils::MakeMaker;
WriteMakefile(
    NAME              => 'Business::PayPal::WPP::ExpressCheckout',
    VERSION_FROM      => 'lib/Business/PayPal/WPP/ExpressCheckout.pm',
    PREREQ_PM         => { SOAP::Lite => 0.67 },
    ($] >= 5.005 ?
      (ABSTRACT_FROM  => 'lib/Business/PayPal/WPP/ExpressCheckout.pm',
       AUTHOR         => 'Scott Wiersdorf <scott@perlcode.org>') : ()),
);
