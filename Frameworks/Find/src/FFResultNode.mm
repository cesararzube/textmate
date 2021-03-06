#import "FFResultNode.h"
#import "attr_string.h"
#import <OakFoundation/NSString Additions.h>
#import <OakAppKit/OakFileIconImage.h>
#import <ns/ns.h>
#import <text/tokenize.h>
#import <text/format.h>
#import <text/utf8.h>
#import <regexp/format_string.h>

static NSAttributedString* PathComponentString (std::string const& path, std::string const& base, NSFont* font)
{
	std::vector<std::string> components;
	std::string str = path::relative_to(path, base);
	for(auto const& component : text::tokenize(str.begin(), str.end(), '/'))
		components.push_back(component);
	if(components.front() == "")
		components.front() = path::display_name("/");
	components.back() = "";

	return ns::attr_string_t()
		<< ns::style::line_break(NSLineBreakByTruncatingMiddle)
		<< font
		<< [NSColor darkGrayColor]
		<< text::join(std::vector<std::string>(components.begin(), components.end()), " ▸ ")
		<< ns::style::bold
		<< (path::is_absolute(path) ? path::display_name(path) : path);
}

static void append (ns::attr_string_t& dst, std::string const& src, size_t from, size_t to, NSFont* font)
{
	size_t begin = from;
	for(size_t i = from; i != to; ++i)
	{
		if(src[i] == '\t' || src[i] == '\r')
		{
			dst.add(src.substr(begin, i-begin));
			if(src[i] == '\t')
			{
				dst.add("\u2003");
			}
			else if(src[i] == '\r')
			{
				dst.add(ns::attr_string_t()
					<< font
					<< [NSColor lightGrayColor]
					<< "<CR>"
				);
			}
			begin = i+1;
		}
	}
	dst.add(src.substr(begin, to-begin));
}

static NSAttributedString* AttributedStringForMatch (std::string const& text, size_t from, size_t to, size_t n, std::string const& newlines, NSFont* font)
{
	ns::attr_string_t str;
	str.add(ns::style::line_break(NSLineBreakByTruncatingTail));
	str.add([NSColor darkGrayColor]);

	// Ensure monospaced digits for the line number prefix
	NSFontDescriptor* descriptor = [font.fontDescriptor fontDescriptorByAddingAttributes:@{
		NSFontFeatureSettingsAttribute: @[ @{ NSFontFeatureTypeIdentifierKey : @(kNumberSpacingType), NSFontFeatureSelectorIdentifierKey : @(kMonospacedNumbersSelector) } ]
	}];

	str.add([NSFont fontWithDescriptor:descriptor size:0]);
	str.add(text::pad(++n, 4) + ": ");
	str.add(font);

	bool inMatch = false;
	size_t last = text.size();
	for(size_t it = 0; it != last; )
	{
		size_t eol = text.find(newlines, it);
		eol = eol != std::string::npos ? eol : last;

		if(oak::cap(it, from, eol) == from)
		{
			append(str, text, it, from, font);
			it = from;
			inMatch = true;
		}

		if(inMatch)
		{
			str.add(ns::style::bold);
			str.add([NSColor blackColor]);
		}

		if(inMatch && oak::cap(it, to, eol) == to)
		{
			append(str, text, it, to, font);
			it = to;
			inMatch = false;

			str.add([NSColor darkGrayColor]);
			str.add(ns::style::unbold);
		}

		append(str, text, it, eol, font);

		if(eol != last)
		{
			str.add("¬");

			if(inMatch)
			{
				str.add([NSColor darkGrayColor]);
				str.add(ns::style::unbold);
			}

			if((eol += newlines.size()) == to)
				inMatch = false;

			if(eol != last)
				str.add("\n" + text::pad(++n, 4) + ": ");
		}

		it = eol;
	}

	return str;
}

@interface FFResultNode ()
{
	document::document_t::callback_t* _callback;
	NSAttributedString* _excerpt;
	NSString* _excerptReplaceString;
	find::match_t _match;
}
@property (nonatomic, readwrite) NSUInteger countOfLeafs;
@property (nonatomic, readwrite) NSUInteger countOfExcluded;
@property (nonatomic, readwrite) NSUInteger countOfReadOnly;
@property (nonatomic, readwrite) NSUInteger countOfExcludedReadOnly;
@end

@implementation FFResultNode
- (instancetype)initWithMatch:(find::match_t const&)aMatch
{
	if(self = [super init])
		_match = aMatch;
	return self;
}

+ (FFResultNode*)resultNodeWithMatch:(find::match_t const&)aMatch baseDirectory:(NSString*)base
{
	FFResultNode* res = [[FFResultNode alloc] initWithMatch:aMatch];
	res.children    = [NSMutableArray array];
	res.displayPath = PathComponentString(base && to_s(base) != find::kSearchOpenFiles && aMatch.document->path() != NULL_STR ? aMatch.document->path() : aMatch.document->display_name(), to_s(base), [NSFont controlContentFontOfSize:0]);
	return res;
}

+ (FFResultNode*)resultNodeWithMatch:(find::match_t const&)aMatch
{
	FFResultNode* res = [[FFResultNode alloc] initWithMatch:aMatch];
	res.countOfLeafs = 1;
	return res;
}

- (void)dealloc
{
	if(_callback)
	{
		self.document->remove_callback(_callback);
		delete _callback;
	}
}

- (void)setCountOfLeafs:(NSUInteger)count             { if(_countOfLeafs            != count) { _parent.countOfLeafs            += count - _countOfLeafs;            _countOfLeafs            = count; } }
- (void)setCountOfExcluded:(NSUInteger)count          { if(_countOfExcluded         != count) { _parent.countOfExcluded         += count - _countOfExcluded;         _countOfExcluded         = count; } }
- (void)setCountOfReadOnly:(NSUInteger)count          { if(_countOfReadOnly         != count) { _parent.countOfReadOnly         += count - _countOfReadOnly;         _countOfReadOnly         = count; } }
- (void)setCountOfExcludedReadOnly:(NSUInteger)count  { if(_countOfExcludedReadOnly != count) { _parent.countOfExcludedReadOnly += count - _countOfExcludedReadOnly; _countOfExcludedReadOnly = count; } }

- (void)addResultNode:(FFResultNode*)aMatch
{
	if(!_children)
	{
		_children = [NSMutableArray array];
		if(_countOfLeafs)
			self.countOfLeafs -= 1;
	}

	aMatch.parent = self;

	[(NSMutableArray*)_children addObject:aMatch];
	self.countOfLeafs            += aMatch.countOfLeafs;
	self.countOfExcluded         += aMatch.countOfExcluded;
	self.countOfReadOnly         += aMatch.countOfReadOnly;
	self.countOfExcludedReadOnly += aMatch.countOfExcludedReadOnly;
}

- (void)removeFromParent
{
	[(NSMutableArray*)_parent.children removeObject:self];
	_parent.countOfExcludedReadOnly -= _countOfExcludedReadOnly;
	_parent.countOfReadOnly         -= _countOfReadOnly;
	_parent.countOfExcluded         -= _countOfExcluded;
	_parent.countOfLeafs            -= _countOfLeafs;
}

- (void)setExcluded:(BOOL)flag
{
	if(_children)
	{
		for(FFResultNode* child in _children)
		{
			if(!child.isReadOnly)
				child.excluded = flag;
		}
	}
	else
	{
		self.countOfExcluded         = flag ? 1 : 0;
		self.countOfExcludedReadOnly = flag && _countOfReadOnly ? 1 : 0;
	}
}

- (BOOL)excluded
{
	return _countOfExcluded == (_children ? _countOfLeafs : 1);
}

- (void)setReadOnly:(BOOL)flag
{
	if(_children)
	{
		for(FFResultNode* child in _children)
			child.readOnly = flag;
	}
	else
	{
		self.countOfReadOnly         = flag ? 1 : 0;
		self.countOfExcludedReadOnly = flag && self.excluded ? 1 : 0;
	}
}

- (BOOL)isReadOnly
{
	return _countOfReadOnly == (_children ? _countOfLeafs : 1);
}

- (FFResultNode*)firstResultNode   { return [_children firstObject]; }
- (FFResultNode*)lastResultNode    { return [_children lastObject]; }
- (find::match_t const&)match      { return _match; }
- (document::document_ptr)document { return _match.document; }
- (NSString*)path                  { return [NSString stringWithCxxString:self.document->path()]; }
- (NSString*)identifier            { return [NSString stringWithCxxString:self.document->identifier()]; }

- (NSUInteger)lineSpan
{
	text::pos_t const from = _match.range.from;
	text::pos_t const to   = _match.range.to;
	return to.line - from.line + (from == to || to.column != 0 ? 1 : 0);
}

- (NSAttributedString*)excerptWithReplacement:(NSString*)replacementString font:(NSFont*)font
{
	if(_excerpt && (replacementString == _excerptReplaceString || [replacementString isEqualToString:_excerptReplaceString]))
		return _excerpt;

	find::match_t const& m = _match;
	size_t from = m.first - m.excerpt_offset;
	size_t to   = m.last  - m.excerpt_offset;

	ASSERT_LE(m.first, m.last);
	ASSERT_LE(from, m.excerpt.size());
	ASSERT_LE(to, m.excerpt.size());

	std::string prefix = m.excerpt.substr(0, from);
	std::string middle = m.excerpt.substr(from, to - from);
	std::string suffix = m.excerpt.substr(to);

	if(m.truncate_head)
		prefix.insert(0, "…");
	if(m.truncate_tail)
		suffix.insert(suffix.size(), "…");

	if(replacementString)
		middle = m.captures.empty() ? to_s(replacementString) : format_string::expand(to_s(replacementString), m.captures);

	if(!utf8::is_valid(prefix.begin(), prefix.end()) || !utf8::is_valid(middle.begin(), middle.end()) || !utf8::is_valid(suffix.begin(), suffix.end()))
	{
		return ns::attr_string_t()
			<< [NSColor darkGrayColor] << font
			<< ns::style::line_break(NSLineBreakByTruncatingTail)
			<< text::format("%zu-%zu: Range is not valid UTF-8, please contact: http://macromates.com/support", m.first, m.last);
	}

	_excerpt = AttributedStringForMatch(prefix + middle + suffix, prefix.size(), prefix.size() + middle.size(), m.line_number, m.newlines, font);
	_excerptReplaceString = replacementString;
	return _excerpt;
}

- (NSImage*)icon
{
	struct document_callback_t : document::document_t::callback_t
	{
		WATCH_LEAKS(document_callback_t);
		document_callback_t (FFResultNode* self) : _self(self) {}
		void handle_document_event (document::document_ptr document, event_t event)
		{
			if(event == did_change_modified_status)
				_self.icon = nil;
		}

	private:
		__weak FFResultNode* _self;
	};

	if(!_icon)
		_icon = [OakFileIconImage fileIconImageWithPath:self.path isModified:self.document->is_modified()];
	if(!_callback)
		self.document->add_callback(_callback = new document_callback_t(self));

	return _icon;
}
@end
