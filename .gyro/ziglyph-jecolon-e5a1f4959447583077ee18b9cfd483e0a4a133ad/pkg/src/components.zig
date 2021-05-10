pub const Alphabetic = @import("components/autogen/DerivedCoreProperties/Alphabetic.zig");
pub const CccMap = @import("components/autogen/DerivedCombiningClass/CccMap.zig");
pub const Control = @import("components/autogen/DerivedGeneralCategory/Control.zig");
pub const DecomposeMap = @import("components/autogen/UnicodeData/DecomposeMap.zig");
pub const GraphemeIterator = @import("zigstr/GraphemeIterator.zig");
pub const Extend = @import("components/autogen/GraphemeBreakProperty/Extend.zig");
pub const ExtPic = @import("components/autogen/emoji-data/ExtendedPictographic.zig");
pub const Format = @import("components/autogen/DerivedGeneralCategory/Format.zig");
pub const HangulMap = @import("components/autogen/HangulSyllableType/HangulMap.zig");
pub const Prepend = @import("components/autogen/GraphemeBreakProperty/Prepend.zig");
pub const Regional = @import("components/autogen/GraphemeBreakProperty/RegionalIndicator.zig");
// Aggregates
pub const Letter = @import("components/aggregate/Letter.zig");
pub const Mark = @import("components/aggregate/Mark.zig");
pub const Number = @import("components/aggregate/Number.zig");
pub const Punct = @import("components/aggregate/Punct.zig");
pub const Symbol = @import("components/aggregate/Symbol.zig");
pub const Width = @import("components/aggregate/Width.zig");
// Letter
pub const CaseFoldMap = @import("components/autogen/CaseFolding/CaseFoldMap.zig");
pub const CaseFold = CaseFoldMap.CaseFold;
pub const Cased = @import("components/autogen/DerivedCoreProperties/Cased.zig");
pub const Lower = @import("components/autogen/DerivedGeneralCategory/LowercaseLetter.zig");
pub const LowerMap = @import("components/autogen/UnicodeData/LowerMap.zig");
pub const ModifierLetter = @import("components/autogen/DerivedGeneralCategory/ModifierLetter.zig");
pub const OtherLetter = @import("components/autogen/DerivedGeneralCategory/OtherLetter.zig");
pub const Title = @import("components/autogen/DerivedGeneralCategory/TitlecaseLetter.zig");
pub const TitleMap = @import("components/autogen/UnicodeData/TitleMap.zig");
pub const Upper = @import("components/autogen/DerivedGeneralCategory/UppercaseLetter.zig");
pub const UpperMap = @import("components/autogen/UnicodeData/UpperMap.zig");
// Mark
pub const Enclosing = @import("components/autogen/DerivedGeneralCategory/EnclosingMark.zig");
pub const Nonspacing = @import("components/autogen/DerivedGeneralCategory/NonspacingMark.zig");
pub const Spacing = @import("components/autogen/DerivedGeneralCategory/SpacingMark.zig");
// Number
pub const Decimal = @import("components/autogen/DerivedGeneralCategory/DecimalNumber.zig");
pub const Digit = @import("components/autogen/DerivedNumericType/Digit.zig");
pub const Hex = @import("components/autogen/PropList/HexDigit.zig");
pub const LetterNumber = @import("components/autogen/DerivedGeneralCategory/LetterNumber.zig");
pub const OtherNumber = @import("components/autogen/DerivedGeneralCategory/OtherNumber.zig");
// Punct
pub const Close = @import("components/autogen/DerivedGeneralCategory/ClosePunctuation.zig");
pub const Connector = @import("components/autogen/DerivedGeneralCategory/ConnectorPunctuation.zig");
pub const Dash = @import("components/autogen/DerivedGeneralCategory/DashPunctuation.zig");
pub const Final = @import("components/autogen/UnicodeData/FinalPunctuation.zig");
pub const Initial = @import("components/autogen/DerivedGeneralCategory/InitialPunctuation.zig");
pub const Open = @import("components/autogen/DerivedGeneralCategory/OpenPunctuation.zig");
pub const OtherPunct = @import("components/autogen/DerivedGeneralCategory/OtherPunctuation.zig");
// Space
pub const WhiteSpace = @import("components/autogen/PropList/WhiteSpace.zig");
// Symbol
pub const Currency = @import("components/autogen/DerivedGeneralCategory/CurrencySymbol.zig");
pub const Math = @import("components/autogen/DerivedGeneralCategory/MathSymbol.zig");
pub const ModifierSymbol = @import("components/autogen/DerivedGeneralCategory/ModifierSymbol.zig");
pub const OtherSymbol = @import("components/autogen/DerivedGeneralCategory/OtherSymbol.zig");
// Width
pub const Ambiguous = @import("components/autogen/DerivedEastAsianWidth/Ambiguous.zig");
pub const Fullwidth = @import("components/autogen/DerivedEastAsianWidth/Fullwidth.zig");
pub const Wide = @import("components/autogen/DerivedEastAsianWidth/Wide.zig");
// UTF-8 string struct
pub const Zigstr = @import("zigstr/Zigstr.zig");
