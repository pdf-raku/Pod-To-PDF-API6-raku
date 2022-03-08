use v6;

use Test;
use Pod::To::PDF::API6;
use PDF::API6;

plan 1;

my $xml = q{<Document>
  <H>
    Abbreviated heading1
  </H>
  <P>
    asdf
  </P>
  <H>
    Paragraph heading1
  </H>
  <P>
    asdf
  </P>
  <Sect>
    <H>
      Subheading2
    </H>
  </Sect>
  <H>
    Delimited heading1
  </H>
  <Sect>
    <Sect>
      <H>
        Heading3
      </H>
      <P>
        asdf
      </P>
    </Sect>
    <H>
      Head2
    </H>
    <P>
      asdf
    </P>
    <Sect>
      <H>
        Head3
      </H>
      <P>
        asdf
      </P>
      <Sect>
        <H>
          Head4
        </H>
        <P>
          asdf
        </P>
      </Sect>
    </Sect>
  </Sect>
</Document>
};

my Pod::To::PDF::API6 $doc .= new: :$=pod;
my PDF::API6 $pdf = $doc.pdf;
$pdf.id = $*PROGRAM-NAME.fmt('%-16.16s');
$pdf.save-as: "t/heading.pdf", :!info;
my PDF::Tags $tags = $doc.tags;

is $tags[0].Str, $xml,
   'Various types of headings convert correctly';

=begin pod
=head1 Abbreviated heading1

asdf

=for head1
Paragraph heading1

asdf

=head2 Subheading2

=begin head1
Delimited
	
heading1
=end head1

=head3 	Heading3

asdf

=head2 Head2

asdf

=head3 Head3

asdf

=head4 Head4

asdf

=end pod
