use v6;

use Test;
use Pod::To::PDF::API6;
use PDF::API6;

plan 1;

my $xml = q{<Document>
  <H2>
    Module Asdf1
  </H2>
  <P>
    This is a module
  </P>
  <P>
    <Code>module Asdf1</Code>
  </P>
  <H3>
    Sub asdf
  </H3>
  <P>
    This is a sub
  </P>
  <P>
    <Code>sub asdf(
    Str $asdf1,
    Str :$asdf2 = "asdf",
) returns Str</Code>
  </P>
  <H2>
    Class Asdf2
  </H2>
  <P>
    This is a class
  </P>
  <P>
    <Code>class Asdf2</Code>
  </P>
  <H3>
    Attribute t
  </H3>
  <P>
    This is an attribute
  </P>
  <P>
    <Code>has Str $.t</Code>
  </P>
  <H3>
    Method asdf
  </H3>
  <P>
    This is a method
  </P>
  <P>
    <Code>method asdf(
    Str :$asdf = "asdf",
) returns Str</Code>
  </P>
</Document>
};

my Pod::To::PDF::API6 $doc .= new: :$=pod;
my PDF::API6 $pdf = $doc.pdf;
$pdf.id = $*PROGRAM-NAME.fmt('%-16.16s');
$pdf.save-as: "t/definition.pdf", :!info;
my PDF::Tags $tags = $doc.tags;

is $tags[0].Str, $xml,
    'Converts definitions correctly';

#| This is a module
module Asdf1 {
    #| This is a sub
    sub asdf(Str $asdf1, Str :$asdf2? = 'asdf') returns Str {
	return '';
    }
}

#| This is a class
class Asdf2 does Positional  {
    #| This is an attribute
    has Str $.t = 'asdf';
    
    #| This is a method
    method asdf(Str :$asdf? = 'asdf') returns Str {
	
    }
}


