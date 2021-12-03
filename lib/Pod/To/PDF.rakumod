class Pod::To::PDF:ver<0.0.1> {
    use PDF::API6;
    use PDF::Tags;
    use PDF::Tags::Elem;
    use PDF::Content;
    use PDF::Content::Color :&color;
    use PDF::Content::Tag :Tags;
    use PDF::Content::Text::Box;
    use Pod::To::PDF::Style;
    use Pod::To::Text;
    # PDF::Class
    use PDF::Destination :Fit;
    use PDF::Page;
    use PDF::StructElem;

    subset Level of Int:D where 1..6;

    has PDF::API6 $.pdf .= new;
    has PDF::Tags $.tags .= create: :$!pdf;
    has PDF::Tags::Elem $.root = $!tags.Document;
    has PDF::Page $!page;
    has PDF::Content $!gfx;
    has UInt $!indent = 0;
    has Pod::To::PDF::Style $.style handles<font font-size leading line-height bold invisible italic mono underline> .= new;
    has $!x;
    has $!y;
    has $.margin = 20;
    has UInt $!pad = 0;
    has @.toc;

    submethod TWEAK {
        $!pdf.creator.push: "{self.^name}-{self.^ver}";
    }

    method render($class: $pod, |c) {
        my PDF::API6 $pdf = pod2pdf($pod, :$class, |c);
	$pdf.Str;
    }

    proto method pod2pdf($p, |) {
        {*}
    }

    sub pod2pdf($pod, :$class = $?CLASS, :$toc = True) is export {
        my $obj = $class.new;
        my $*tag = $obj.root;
        $obj.pod2pdf($pod);
        if $toc && $obj.toc {
            $obj.pdf.outlines.kids = $obj.toc;
        }
        $obj.pdf;
    }

    my constant vpad = 2;
    my constant hpad = 10;
    
    sub fit-widths($width is copy, @widths) {
        my $cell-width = $width / +@widths;
        my @idx;

        for @widths.pairs {
            if .value <= $cell-width {
                $width -= .value;
            }
            else {
                @idx.push: .key;
            }
        }

        if @idx {
            if @idx < @widths {
                my @over;
                my $i = 0;
                @over[$_] := @widths[ @idx[$_] ]
                    for  ^+@idx;
                fit-widths($width, @over);
            }
            else {
                $_ = $cell-width
                      for @widths;
            }
        }
    }

    method !table-row(@row, @widths, Bool :$header) {
        if +@row -> \cols {
            my @overflow;
            # simple fixed column widths, for now
            my $tab = $!margin + self!indent;
            my $row-height = 0;
            my $height = $!y - $!margin;
            my $name = $header ?? TableHeader !! TableData;

            for ^cols {
                my $width = @widths[$_];
                temp $*tag = $*tag[$_] // $*tag.add-kid: :$name;

                if @row[$_] -> $tb is rw {
                    if $tb.width > $width || $tb.height > $height {
                        $tb .= clone: :$width, :$height;
                    }
                    self!mark: {
                        self!gfx.print: $tb, :position[$tab, $!y];
                        self!underline: $tb, :$tab, :$width
                            if $header;
                    }
                    given $tb.content-height {
                        $row-height = $_ if $_ > $row-height;
                    }
                    if $tb.overflow -> $overflow {
                        my $text = $overflow.join;
                        @overflow[$_] = $tb.clone: :$text, :$width, :height(0);
                    }
                }
                $tab += $width + hpad;
            }
            if @overflow {
                self!table-row(@overflow, @widths, :$header);
            }
            else {
                $!y -= $row-height + vpad;
            }
        }
    }

    method !table-cell($pod) {
        my $text = pod2text($pod);
        self!text-box: $text, :width(0), :height(0), :indent(0);
    }

    method !build-table($pod, @table) {
        my $x0 = $!margin + self!indent;
        my \total-width = self!gfx.canvas.width - $x0 - $!margin;
        @table = ();
 
        self!style: :bold, {
            my @row = $pod.headers.map: { self!table-cell($_) }
            @table.push: @row;
        }
 
        $pod.contents.map: {
            my @row = .map: { self!table-cell($_) }
            @table.push: @row;
        }

        my $cols = @table.max: *.Int;
        my @widths = (^$cols).map: -> $col { @table.map({.[$col].?width // 0}).max };
       fit-widths(total-width - hpad * (@widths-1), @widths);
       @widths;
    }

    multi method pod2pdf(Pod::Block::Table $pod) {
        my @widths = self!build-table: $pod, my @table;
        
        $.pad: {
            temp $*tag .= Table;
            if $pod.caption -> $caption {
                temp $*tag .= Caption;
                $.say: $caption;
            }
            my PDF::Content::Text::Box @header = @table.shift.List;
            if @header {
                temp $*tag .= TableHead;
                $*tag .= TableRow;
                self!table-row: @header, @widths, :header;
            }

            if @table {
                temp $*tag .= TableBody;
                for @table {
                    my @row = .List;
                    if @row {
                        temp $*tag .= TableRow;
                        self!table-row: @row, @widths;
                    }
                }
            }
        }
    }

    multi method pod2pdf(Pod::Block::Named $pod) {
        given $pod.name {
            when 'pod'  { $.pod2pdf($pod.contents)     }
            when 'para' {
                $.pod2pdf: $pod.contents;
            }
            when 'config' { }
            when 'nested' {
                self!style: :indent, {
                    $.pod2pdf: $pod.contents;
                }
            }
            default     {
                given $pod.name {
                    when 'TITLE' {
                        my $title = pod2text($pod.contents);
                        $!pdf.info.Title = $title;
                        $.pad: {
                            self!heading: pod2text($pod.contents), :level(1);
                        }
                    }
                    when 'SUBTITLE' {
                        $.pad: {
                            self!heading: pod2text($pod.contents), :level(2);
                        }
                    }
                    default {
                        warn "unrecognised POD named block: $_";
                        $.say($_);
                        $.pod2pdf($pod.contents);
                    }
                }
            }
        }
    }

    multi method pod2pdf(Pod::Block::Code $pod) {
        $.pad: {
            self!code: $pod.contents.join;
        }
    }

    multi method pod2pdf(Pod::Heading $pod) {
        $.pad: {
            my Level $level = min($pod.level, 6);
            self!heading( node2text($pod.contents), :$level);
        }
    }

    multi method pod2pdf(Pod::Block::Para $pod) {
        $.pad: {
            self!style: :tag(Paragraph), {
                $.pod2pdf($pod.contents);
            }
        }
    }

    multi method pod2pdf(Pod::FormattingCode $pod) {
        given $pod.type {
            when 'B' {
                temp $.bold = True;
                $.pod2pdf($pod.contents);
            }
            when 'C' {
                temp $.mono = True;
                $.pod2pdf($pod.contents);
            }
            when 'I' {
                temp $.italic = True;
                $.pod2pdf($pod.contents);
            }
            when 'U' {
                temp $.underline = True;
                $.pod2pdf($pod.contents);
            }
            when 'Z' {
                temp $.invisible = True;
                $.pod2pdf($pod.contents);
            }
            when 'L' {
                my $x = $!x;
                my $y = $!y;
                my $text = pod2text($pod.contents);
                my @rect;
                self!mark: :name<Link>, {
                    my ($x, $y, \w, \h) = @.print($text);
                    $y -= ($.leading - 1) * $.font-size;
                    @rect = self!gfx.base-coords: $x,  $y,  $x+w,  $y+h;
                }
                # Todo /QuadPoint regions for line-spanning links
                # see PDF ISO32000 14.8.4.4.2 Link Elements

                given $pod.meta.head // $text -> $uri {
                    my $action = $!pdf.action: :$uri;
                    $!pdf.annotation(
                        :$!page,
                        :$action,
                        :@rect,
                    );
                }
            }
            default {
                warn "todo: POD formatting code: $_";
                $.pod2pdf($pod.contents);
            }
        }
    }

    multi method pod2pdf(Pod::Item $pod) {
        $.pad: {
            self!style: :tag(ListItem), {
                $*tag.Lbl.mark: self!gfx, {
                    my constant BulletPoints = ("\c[BULLET]", "\c[WHITE BULLET]", '-');
                    my Level $list-level = min($pod.level // 1, 3);
                    my $bp = BulletPoints[$list-level - 1];
                    .print: $bp, |self!text-position;
                }

                self!style: :tag(ListBody), :indent, {
                    $.pod2pdf($pod.contents);
                }
            }
        }
    }

    multi method pod2pdf(Pod::Block::Declarator $pod) {
        my $w := $pod.WHEREFORE;
        my Level $level = 3;
        my ($type, $code, $name, $decl) = do given $w {
            when Method {
                my @params = .signature.params.skip(1);
                @params.pop if @params.tail.name eq '%_';
                (
                    (.multi ?? 'multi ' !! '') ~ 'method',
                    .name ~ signature2text(@params, .returns),
                )
            }
            when Sub {
                (
                    (.multi ?? 'multi ' !! '') ~ 'sub',
                    .name ~ signature2text(.signature.params, .returns)
                )
            }
            when Attribute {
                my $gist = .gist;
                my $name = .name.subst('$!', '');
                $gist .= subst('!', '.')
                    if .has_accessor;

                ('attribute', $gist, $name, 'has');
            }
            when .HOW ~~ Metamodel::EnumHOW {
                ('enum', .raku() ~ signature2text($_.enums.pairs));
            }
            when .HOW ~~ Metamodel::ClassHOW {
                $level = 2;
                ('class', .raku, .^name);
            }
            when .HOW ~~ Metamodel::ModuleHOW {
                $level = 2;
                ('module', .raku, .^name);
            }
            when .HOW ~~ Metamodel::SubsetHOW {
                ('subset', .raku ~ ' of ' ~ .^refinee().raku);
            }
            when .HOW ~~ Metamodel::PackageHOW {
                ('package', .raku)
            }
            default {
                '', ''
            }
        }

        $name //= $w.?name // '';
        $decl //= $type;

        $.pad: {
            self!style: :tag(Section), {
                self!heading($type.tclc ~ ' ' ~ $name, :$level);

                if $code {
                    $.pad(1);
                    self!code($decl ~ ' ' ~ $code);
                }

                if $pod.contents {
                    $.pad(1);
                    self!style: :tag(Paragraph), {
                        $.pod2pdf($pod.contents);
                    }
                }
            }
        }
    }

    sub signature2text($params, Mu $returns?) {
        my constant NL = "\n    ";
        my $result = '(';

        if $params.elems {
            $result ~= NL ~ $params.map(&param2text).join(NL) ~ "\n";
        }
        $result ~= ')';
        unless $returns<> =:= Mu {
            $result ~= " returns " ~ $returns.raku
        }
        $result;
    }
    sub param2text($p) {
        $p.raku ~ ',' ~ ( $p.WHY ?? ' # ' ~ $p.WHY !! ' ')
    }

    multi method pod2pdf(Array $pod) {
        for $pod.list {
            $.pod2pdf($_);
        };
    }

    multi method pod2pdf(Str $pod) {
        $.print($pod);
    }

    multi method pod2pdf($pod) {
        warn "fallback render of {$pod.WHAT.raku}";
        $.say: pod2text($pod);
    }

    multi method say {
        $!x = 0;
        $!y -= $.line-height;
    }
    multi method say(Str $text, |c) {
        @.print($text, :nl, |c);
    }

    multi method pad(&codez) { $.pad; &codez(); $.pad}
    multi method pad($!pad = 2) { }
    method !text-box(
        Str $text,
        :$width = self!gfx.canvas.width - self!indent - 2*$!margin,
        :$height = $!y - $!margin,
        |c) {
        PDF::Content::Text::Box.new: :$text, :indent($!x), :$.leading, :$.font, :$.font-size, :$width, :$height, |c;
    }

    method print(Str $text, Bool :$nl, |c) {
        $.say for ^$!pad;
        $!pad = 0;
        my PDF::Content::Text::Box $tb = self!text-box: $text, |c;
        my $w = $tb.content-width;
        my $h = $tb.content-height;

        unless $.invisible {
            self!mark: {
                self!gfx.print: $tb, |self!text-position(), :$nl;
                self!underline: $tb
                    if $.underline;
            }
        }

        if $tb.overflow {
            $.say() unless $nl;
            @.print: $tb.overflow.join;
        }
        else {
            # calculate text bounding box and advance x, y
            my $lines = +$tb.lines;
            my $x0 = $!margin + self!indent;
            $x0 += $!x if $lines <= 1;
            if $nl {
                # advance to next line
                $!x = 0;
            }
            else {
                # continue this line
                with $tb.lines.pop {
                    $w = .content-width - .indent;
                    $!x += $w + $tb.space-width;
                }
            }
            $!y -= $tb.content-height;
            my $y0 = $!y;

            ($x0, $y0, $w, $h);
        }
    }

    method !text-position {
        :position[$!margin + self!indent, $!y]
    }

    method !mark(&action, |c) {
        given self!gfx {
            if .open-tags.first(*.mcid.defined) {
                # caller is already marking
                action($_);
            }
            else {
                $*tag.mark: $_, &action, |c;
            }
        }
    }

    method !style(&codez, Bool :$indent, Str :$tag, |c) {
        temp $!style .= clone: |c;
        temp $!indent;
        temp $*tag;
        $*tag .= add-kid: :name($_) with $tag;
        $!indent += 1 if $indent;
        &codez();
    }

    method !add-toc-entry(Hash $entry, Level $level, @kids = @!toc, Level :$cur = 1, ) {
        if $level == $cur {
            @kids.push: $entry;
        }
        else {
            # descend
            @kids.push({}) unless @kids;
            @kids.tail<kids> //= [];
            self!add-toc-entry($entry, $level, :cur($cur+1), @kids.tail<kids>);
        }
    }

    method !heading(Str:D $Title, Level :$level = 2, :$underline = $level == 1) {
        self!style: :tag('H' ~ $level), :$underline, {
            my constant HeadingSizes = 20, 16, 13, 11.5, 10, 10;
            $.font-size = HeadingSizes[$level - 1];
            self!new-page if $level == 1;

            if $level < 5 {
                $.bold = True;
            }
            else {
                $.italic = True;
            }

            my (\x, \y, \w, \h) = @.say($Title);
            my ($left, $top) = $!gfx.base-coords: x, y+h + $.line-height;
            # Register in table of contents
            my PDF::Destination $dest = $!pdf.destination: :$!page, :fit(FitBoxHoriz), :$top;
            my PDF::StructElem $SE = $*tag.cos;
            self!add-toc-entry: { :$Title, :$dest, :$SE  }, $level;
        }
    }

    method !code(Str $raw) {
        self!style: :mono, :indent, :tag(CODE), {
            my constant \pad = 5;
            $.font-size *= .8;
            my $gfx = self!gfx;
            my (\x, \y, \w, \h) = @.say($raw.chomp, :verbatim);

            my $x0 =  self!indent + $!margin + $!x;
            my $width = self!gfx.canvas.width - $!margin - $x0;
            $gfx.graphics: {
                constant \pad = 2;
                .FillColor = color 0;
                .StrokeColor = color 0;
                .FillAlpha = 0.1;
                .StrokeAlpha = 0.25;
                .Rectangle: $x0 - pad, y - pad, $width, h + 2*pad + $.line-height;
                .paint: :fill, :stroke;
            }
        }
    }

    method !line($x0, $y0, $x1, $y1 = $y0, :$linewidth = 1) {
        given self!gfx {
            .Save;
            .SetLineWidth: $linewidth;
            .MoveTo: $x0, $y0;
            .LineTo: $x1, $y1;
            .Stroke;
            .Restore;
        }
    }

    method !underline(PDF::Content::Text::Box $tb, :$tab = $!margin, :$width) {
        my $y = $!y + $tb.underline-position;
        my $linewidth = $tb.underline-thickness;
        for $tb.lines {
            my $x0 = $tab + .indent;
            my $x1 = $tab + ($width // .content-width);
            self!line($x0, $y, $x1, :$linewidth);
            $y -= .height * $tb.leading;
        }
    }

    method !gfx {
        if !$!page.defined || $!y <= 2 * $!margin {
            self!new-page;
        }
        elsif $!x > 0 && $!x > $!gfx.canvas.width - self!indent - $!margin {
            self.say;
        }
        $!gfx;
    }

    method !new-page {
        $!page = $!pdf.add-page;
        $!gfx = $!page.gfx;
        $!x = 0;
        $!y = $!page.height - 2 * $!margin;
        # suppress whitespace before significant content
        $!pad = 0;
    }

    method !indent {
        10 * $!indent;
    }

    multi sub node2text(Pod::Block $_) { node2text(.contents) }
    multi sub node2text(@pod) { @pod.map(&node2text).join: ' ' }
    multi sub node2text(Str() $_) { .trim }
}

=NAME
Pod::To::PDF - Render Pod as PDF

=begin SYNOPSIS
From command line:

    $ raku --doc=PDF lib/to/class.rakumod | raku -e'"class.pdf".IO.spurt: $*IN.slurp.encode("latin-1")' > to-class.pdf

From Raku:
    =begin code :lang<raku>
    use Pod::To::PDF;

    =NAME
    foobar.pl

    =SYNOPSIS
        foobar.pl <options> files ...

    pod2pdf($=pod).save-as: "foobar.pdf";
    =end code
=end SYNOPSIS

=begin EXPORTS
    class Pod::To::PDF;
    sub pod2pdf; # See below
=end EXPORTS

=begin DESCRIPTION
This is a fully featured module for rendering POD to PDF.

The pdf2pdf() function returns a PDF::API6 object which can be further
manipulated, or saved to a PDF file.

    use PDF::API6;
    my PDF::API6 $pdf = pod2pdf($=pod);
    $pdf.save-as: "class.pdf"
                
The render() method returns a byte string which can be written to a
`latin-1` encoded file.

    "class.pdf".IO.spurt: Pod::To::PDF.render($=pod), :enc<latin-1>;

=end DESCRIPTION
