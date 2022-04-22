//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import XCTest
import _StringProcessing
@testable import RegexBuilder

class RegexDSLTests: XCTestCase {
  func _testDSLCaptures<Content: RegexComponent, MatchType>(
    _ tests: (input: String, expectedCaptures: MatchType?)...,
    matchType: MatchType.Type,
    _ equivalence: (MatchType, MatchType) -> Bool,
    file: StaticString = #file,
    line: UInt = #line,
    @RegexComponentBuilder _ content: () -> Content
  ) throws {
    let regex = content()
    for (input, maybeExpectedCaptures) in tests {
      let maybeMatch = input.wholeMatch(of: regex)
      if let expectedCaptures = maybeExpectedCaptures {
        let match = try XCTUnwrap(maybeMatch, file: file, line: line)
        XCTAssertTrue(
          type(of: regex).RegexOutput.self == MatchType.self,
          """
          Expected match type: \(MatchType.self)
          Actual match type: \(type(of: regex).RegexOutput.self)
          """)
        let captures = try XCTUnwrap(match.output as? MatchType, file: file, line: line)
        XCTAssertTrue(
          equivalence(captures, expectedCaptures),
          "'\(captures)' is not equal to the expected '\(expectedCaptures)'.",
          file: file, line: line)
      } else {
        XCTAssertNil(maybeMatch, file: file, line: line)
      }
    }
  }

  func testSimpleStrings() throws {
    let regex = Regex {
      "a"
      Capture(Character("b")) // Character
      TryCapture("1") { Int($0) } // Int
    }
    // Assert the inferred capture type.
    let _: (Substring, Substring, Int).Type = type(of: regex).RegexOutput.self
    let maybeMatch = "ab1".wholeMatch(of: regex)
    let match = try XCTUnwrap(maybeMatch)
    XCTAssertTrue(match.output == ("ab1", "b", 1))

    let substring = "ab1"[...]
    let substringMatch = try XCTUnwrap(substring.wholeMatch(of: regex))
    XCTAssertTrue(match.output == substringMatch.output)
  }

  func testCharacterClasses() throws {
    try _testDSLCaptures(
      ("a c", ("a c", " ", "c")),
      matchType: (Substring, Substring, Substring).self, ==)
    {
      .any
      Capture(.whitespace) // Substring
      Capture("c") // Substring
    }
    
    try _testDSLCaptures(
      ("abc1def2", "abc1def2"),
      matchType: Substring.self, ==)
    {
      // First group
      OneOrMore {
        CharacterClass("a"..."z", .digit)
      }

      // Second group
      OneOrMore {
        ChoiceOf {
          "a"..."z"
          CharacterClass.hexDigit
        }
      }
    }

    try _testDSLCaptures(
      ("abc1def2", ("abc1def2", "abc1")),
      matchType: (Substring, Substring).self, ==)
    {
      Capture {
        OneOrMore(.digit.inverted)
        ("a"..."z").inverted
      }

      OneOrMore {
        CharacterClass.whitespace.inverted
      }
    }
  }

  func testCharacterClassOperations() throws {
    try _testDSLCaptures(
      ("bcdefn1a", "bcdefn1a"),
      ("nbcdef1a", nil),        // fails symmetric difference lookahead
      ("abcdef1a", nil),        // fails union
      ("bcdef3a", nil),         // fails subtraction
      ("bcdef1z", nil),         // fails intersection
      matchType: Substring.self, ==)
    {
      let disallowedChars = CharacterClass.hexDigit
        .symmetricDifference("a"..."z")
      Lookahead(disallowedChars, negative: true)      // No: 0-9 + g-z

      OneOrMore(("b"..."g").union("d"..."n"))         // b-n
      
      CharacterClass.digit.subtracting("3"..."9")     // 1, 2, non-ascii digits

      CharacterClass.hexDigit.intersection("a"..."z") // a-f
    }
  }

  func testMatchResultDotZeroWithoutCapture() throws {
    let match = try XCTUnwrap("aaa".wholeMatch { OneOrMore { "a" } })
    XCTAssertEqual(match.0, "aaa")
  }

  func testAlternation() throws {
    do {
      let regex = ChoiceOf {
        "aaa"
      }
      XCTAssertTrue("aaa".wholeMatch(of: regex)?.output == "aaa")
      XCTAssertNil("aab".wholeMatch(of: regex)?.output)
    }
    do {
      let regex = ChoiceOf {
        "aaa"
        "bbb"
        "ccc"
      }
      XCTAssertTrue("aaa".wholeMatch(of: regex)?.output == "aaa")
      XCTAssertNil("aab".wholeMatch(of: regex)?.output)
      XCTAssertTrue("bbb".wholeMatch(of: regex)?.output == "bbb")
      XCTAssertTrue("ccc".wholeMatch(of: regex)?.output == "ccc")
    }
    do {
      let regex = Regex {
        "ab"
        OneOrMore {
          Capture {
            ChoiceOf {
              "c"
              "def"
            }
          }
        }
      }
      XCTAssertTrue(
        try XCTUnwrap("abc".wholeMatch(of: regex)?.output) == ("abc", "c"))
    }
    do {
      let regex = ChoiceOf {
        "aaa"
        "bbb"
        "ccc"
      }
      XCTAssertTrue("aaa".wholeMatch(of: regex)?.output == "aaa")
      XCTAssertNil("aab".wholeMatch(of: regex)?.output)
      XCTAssertTrue("bbb".wholeMatch(of: regex)?.output == "bbb")
      XCTAssertTrue("ccc".wholeMatch(of: regex)?.output == "ccc")
    }
    do {
      let regex = ChoiceOf {
        Capture("aaa")
      }
      XCTAssertTrue(
        try XCTUnwrap("aaa".wholeMatch(of: regex)?.output) == ("aaa", "aaa"))
      XCTAssertNil("aab".wholeMatch(of: regex)?.output)
    }
    do {
      let regex = ChoiceOf {
        Capture("aaa")
        Capture("bbb")
        Capture("ccc")
      }
      XCTAssertTrue(
        try XCTUnwrap("aaa".wholeMatch(of: regex)?.output) == ("aaa", "aaa", nil, nil))
      XCTAssertTrue(
        try XCTUnwrap("bbb".wholeMatch(of: regex)?.output) == ("bbb", nil, "bbb", nil))
      XCTAssertTrue(
        try XCTUnwrap("ccc".wholeMatch(of: regex)?.output) == ("ccc", nil, nil, "ccc"))
      XCTAssertNil("aab".wholeMatch(of: regex)?.output)
    }
  }

  func testCombinators() throws {
    try _testDSLCaptures(
      ("aaaabccccdddkj", ("aaaabccccdddkj", "b", "cccc", "d", "k", nil, "j")),
      matchType: (Substring, Substring, Substring, Substring?, Substring, Substring?, Substring?).self, ==)
    {
      OneOrMore("a")
      Capture(OneOrMore(Character("b"))) // Substring
      Capture(ZeroOrMore("c")) // Substring
      ZeroOrMore(Capture(.hexDigit)) // Substring?
      Optionally("e")
      Capture {
        ChoiceOf {
          "t"
          "k"
        }
      } // Substring
      ChoiceOf { Capture("k"); Capture("j") } // (Substring?, Substring?)
    }
  }
  
  func testOptions() throws {
    try _testDSLCaptures(
      ("abc", "abc"),
      ("ABC", "ABC"),
      ("abcabc", "abcabc"),
      ("abcABCaBc", "abcABCaBc"),
      matchType: Substring.self, ==) {
        OneOrMore {
          "abc"
        }.ignoresCase(true)
      }
    
    // Multiple options on one component wrap successively, but do not
    // override - equivalent to each option attached to a wrapping `Regex`.
    try _testDSLCaptures(
      ("abc", "abc"),
      ("ABC", "ABC"),
      ("abcabc", "abcabc"),
      ("abcABCaBc", "abcABCaBc"),
      matchType: Substring.self, ==) {
        OneOrMore {
          "abc"
        }
        .ignoresCase(true)
        .ignoresCase(false)
      }

    // An option on an outer component doesn't override an option set on an
    // inner component.
    try _testDSLCaptures(
      ("abc", "abc"),
      ("ABC", "ABC"),
      ("ABCde", "ABCde"),
      ("ABCDE", nil),
      ("abcabc", "abcabc"),
      ("abcdeABCdeaBcde", "abcdeABCdeaBcde"),
      matchType: Substring.self, ==) {
        OneOrMore {
          "abc".ignoresCase(true)
          Optionally("de")
        }
        .ignoresCase(false)
      }
    
#if os(macOS)
    try XCTExpectFailure("Implement level 2 word boundaries") {
      try _testDSLCaptures(
        ("can't stop won't stop", ("can't stop won't stop", "can't", "won")),
        matchType: (Substring, Substring, Substring).self, ==) {
          Capture {
            OneOrMore(.word)
            Anchor.wordBoundary
          }
          OneOrMore(.any, .reluctant)
          "stop"
          " "
          
          Capture {
            OneOrMore(.word)
            Anchor.wordBoundary
          }
          .wordBoundaryKind(.unicodeLevel1)
          OneOrMore(.any, .reluctant)
          "stop"
        }
    }
#endif
    
    try _testDSLCaptures(
      ("abcdef123", ("abcdef123", "a", "123")),
      matchType: (Substring, Substring, Substring).self, ==) {
        Capture {
          // Reluctant behavior due to option
          OneOrMore(.anyOf("abcd"))
            .repetitionBehavior(.reluctant)
        }
        ZeroOrMore("a"..."z")
        
        Capture {
          // Eager behavior due to explicit parameter, despite option
          OneOrMore(.digit, .eager)
            .repetitionBehavior(.reluctant)
        }
        ZeroOrMore(.digit)
      }
    
    try _testDSLCaptures(
      ("abcdefg", ("abcdefg", "abcdefg")),
      ("abcdéfg", ("abcdéfg", "abcd")),
      matchType: (Substring, Substring).self, ==) {
        Capture {
          OneOrMore(.word)
        }
        .asciiOnlyWordCharacters()
        
        ZeroOrMore(.any)
      }
  }
  
  func testQuantificationBehavior() throws {
    // Eager by default
    try _testDSLCaptures(
      ("abc1def2", ("abc1def2", "2")),
      matchType: (Substring, Substring).self, ==)
    {
      OneOrMore(.word)
      Capture(.digit)
      ZeroOrMore(.any)
    }

    // Explicitly reluctant
    try _testDSLCaptures(
      ("abc1def2", ("abc1def2", "1")),
      matchType: (Substring, Substring).self, ==)
    {
      OneOrMore(.word, .reluctant)
      Capture(.digit)
      ZeroOrMore(.any)
    }
    // Explicitly reluctant overrides default option
    try _testDSLCaptures(
      ("abc1def2", ("abc1def2", "1")),
      matchType: (Substring, Substring).self, ==)
    {
      OneOrMore(.reluctant) {
        .word
      }.repetitionBehavior(.possessive)
      Capture(.digit)
      ZeroOrMore(.any)
    }
    // Default set to reluctant
    try _testDSLCaptures(
      ("abc1def2", ("abc1def2", "1")),
      matchType: (Substring, Substring).self, ==)
    {
      Regex {
        OneOrMore(.word)
        Capture(.digit)
        ZeroOrMore(.any)
      }.repetitionBehavior(.reluctant)
    }
    // Default set to reluctant applies to regex syntax
    try _testDSLCaptures(
      ("abc1def2", ("abc1def2", "1")),
      matchType: (Substring, Substring).self, ==)
    {
      try! Regex(#"\w+(\d).*"#, as: (Substring, Substring).self)
        .repetitionBehavior(.reluctant)
    }
    
    // Explicitly possessive
    try _testDSLCaptures(
      ("aaaa", nil),
      matchType: Substring.self, ==)
    {
      Regex {
        OneOrMore("a", .possessive)
        "a"
      }
    }
    // Default set to possessive
    try _testDSLCaptures(
      ("aaaa", nil),
      matchType: Substring.self, ==)
    {
      Regex {
        OneOrMore("a")
        "a"
      }.repetitionBehavior(.possessive)
    }
    // More specific default set to eager
    try _testDSLCaptures(
      ("aaaa", ("aaaa", "aaa")),
      matchType: (Substring, Substring).self, ==)
    {
      Regex {
        Capture {
          OneOrMore("a")
            .repetitionBehavior(.eager)
        }
        OneOrMore("a")
      }.repetitionBehavior(.possessive)
    }
    // More specific default set to reluctant
    try _testDSLCaptures(
      ("aaaa", ("aaaa", "a")),
      matchType: (Substring, Substring).self, ==)
    {
      Regex {
        Capture {
          OneOrMore("a")
            .repetitionBehavior(.reluctant)
        }
        OneOrMore("a")
      }.repetitionBehavior(.possessive)
    }

    try _testDSLCaptures(
      ("abc1def2", "abc1def2"),
      matchType: Substring.self, ==)
    {
      Repeat(2...) {
        Repeat(count: 3) {
          CharacterClass.word
        }
        CharacterClass.digit
      }
    }
    
    try _testDSLCaptures(
      ("aaabbbcccdddeeefff", "aaabbbcccdddeeefff"),
      ("aaaabbbcccdddeeefff", nil),
      ("aaacccdddeeefff", nil),
      ("aaabbbcccccccdddeeefff", nil),
      ("aaabbbcccddddddeeefff", nil),
      ("aaabbbcccdddefff", nil),
      ("aaabbbcccdddeee", "aaabbbcccdddeee"),
      matchType: Substring.self, ==)
    {
      Repeat(count: 3) { "a" }
      Repeat(1...) { "b" }
      Repeat(2...5) { "c" }
      Repeat(..<5) { "d" }
      Repeat(2...) { "e" }
      Repeat(0...) { "f" }
    }
    
    let octoDecimalRegex: Regex<(Substring, Int?)> = Regex {
      let charClass = CharacterClass(.digit, "a"..."h")//.ignoringCase()
      Capture {
        OneOrMore(charClass)
      } transform: { Int($0, radix: 18) }
    }
    XCTAssertEqual("ab12".firstMatch(of: octoDecimalRegex)!.output.1, 61904)
  }
  
  func testAssertions() throws {
    try _testDSLCaptures(
      ("aaaaab", "aaaaab"),
      ("caaaaab", nil),
      ("aaaaabc", nil),
      matchType: Substring.self, ==)
    {
      Anchor.startOfLine
      OneOrMore("a")
      "b"
      Anchor.endOfLine
    }
    
    try _testDSLCaptures(
      ("Cafe\u{301}", nil),
      ("Cafe", "Cafe"),
      matchType: Substring.self, ==)
    {
      OneOrMore(.word)
      UnicodeScalar("e")
      Anchor.textSegmentBoundary
    }

    try _testDSLCaptures(
      ("aaaaa1", "aaaaa1"),
      ("aaaaa2", nil),
      ("aaaaa", nil),
      ("aaaaab", nil),
      matchType: Substring.self, ==)
    {
      OneOrMore("a")
      Lookahead(CharacterClass.digit)
      Lookahead("2", negative: true)
      CharacterClass.word
    }
  }

  func testNestedGroups() throws {
    return;

    // TODO: clarify what the nesting story is

    /*
    try _testDSLCaptures(
      ("aaaabccccddd", ("aaaabccccddd", [("b", "cccc", ["d", "d", "d"])])),
      matchType: (Substring, [(Substring, Substring, [Substring])]).self, ==)
    {
      "a".+
      OneOrMore {
        Capture(OneOrMore("b"))
        Capture(ZeroOrMore("c"))
        Capture("d").*
        "e".?
      }
    }
     */
  }

  func testCapturelessQuantification() throws {
    // This test is to make sure that a captureless quantification, when used
    // straight out of the quantifier (without being wrapped in a builder), is
    // able to produce a regex whose `Match` type does not contain any sort of
    // void.
    let regex = ZeroOrMore(.digit)
    // Assert the inferred capture type.
    let _: Substring.Type = type(of: regex).RegexOutput.self
    let input = "123123"
    let match = try XCTUnwrap(input.wholeMatch(of: regex)?.output)
    XCTAssertTrue(match == input)
  }

  func testQuantificationWithTransformedCapture() throws {
    // This test is to make sure transformed capture type information is
    // correctly propagated from the DSL into the bytecode and that the engine
    // is reconstructing the right types upon quantification (both empty and
    // non-empty).
    enum Word: Int32 {
      case apple
      case orange

      init?(_ string: Substring) {
        switch string {
        case "apple": self = .apple
        case "orange": self = .orange
        default: return nil
        }
      }
    }
    try _testDSLCaptures(
      ("aaa 123 apple orange apple", ("aaa 123 apple orange apple", 123, .apple)),
      ("aaa     ", ("aaa     ", nil, nil)),
      matchType: (Substring, Int?, Word?).self, ==)
    {
      OneOrMore("a")
      OneOrMore(.whitespace)
      Optionally {
        Capture(OneOrMore(.digit)) { Int($0)! }
      }
      ZeroOrMore {
        OneOrMore(.whitespace)
        Capture(OneOrMore(.word)) { Word($0)! }
      }
    }
  }

  func testNestedCaptureTypes() throws {
    let regex1 = Regex {
      OneOrMore("a")
      Capture {
        Capture(OneOrMore("b"))
        Optionally("e")
      }
    }
    let _: (Substring, Substring, Substring).Type
      = type(of: regex1).RegexOutput.self
    let regex2 = Regex {
      OneOrMore("a")
      Capture {
        ZeroOrMore {
          TryCapture("b") { Int($0) }
        }
        Optionally("e")
      }
    }
    let _: (Substring, Substring, Int?).Type
      = type(of: regex2).RegexOutput.self
    let regex3 = Regex {
      OneOrMore("a")
      Capture {
        TryCapture("b") { Int($0) }
        ZeroOrMore {
          TryCapture("c") { Double($0) }
        }
        Optionally("e")
      }
    }
    let _: (Substring, Substring, Int, Double?).Type
      = type(of: regex3).RegexOutput.self
    let regex4 = Regex {
      OneOrMore("a")
      Capture {
        OneOrMore {
          Capture(OneOrMore("b"))
          Capture(ZeroOrMore("c"))
          ZeroOrMore(Capture("d"))
          Optionally("e")
        }
      }
    }
    let _: (
      Substring, Substring, Substring, Substring, Substring?).Type
      = type(of: regex4).RegexOutput.self
  }

  func testUnicodeScalarPostProcessing() throws {
    let spaces = Regex {
      ZeroOrMore {
        .whitespace
      }
    }

    let unicodeScalar = Regex {
      OneOrMore {
        .hexDigit
      }
      spaces
    }

    let unicodeData = Regex {
      unicodeScalar
      Optionally {
        ".."
        unicodeScalar
      }

      ";"
      spaces

      Capture {
        OneOrMore {
          .word
        }
      }

      ZeroOrMore {
        .any
      }
    }

    // Assert the inferred capture type.
    let _: (Substring, Substring).Type = type(of: unicodeData).RegexOutput.self

    let unicodeLine =
      "1BCA0..1BCA3  ; Control # Cf   [4] SHORTHAND FORMAT LETTER OVERLAP..SHORTHAND FORMAT UP STEP"
    let match = try XCTUnwrap(unicodeLine.wholeMatch(of: unicodeData))
    XCTAssertEqual(match.0, Substring(unicodeLine))
    XCTAssertEqual(match.1, "Control")
  }

  func testGraphemeBreakData() throws {
    let line = """
      A6F0..A6F1    ; Extend # Mn   [2] BAMUM COMBINING MARK KOQNDON..BAMUM COMBINING MARK TUKWENTIS
      """
    
    let regexWithCapture = Regex {
      Capture {
        OneOrMore(.hexDigit)
      } transform: { Unicode.Scalar(hex: $0) }
      Optionally {
        ".."
        Capture {
          OneOrMore(.hexDigit)
        } transform: { Unicode.Scalar(hex: $0) }
      }
      OneOrMore(.whitespace)
      ";"
      OneOrMore(.whitespace)
      Capture(OneOrMore(.word))
      ZeroOrMore(.any)
    } // Regex<(Substring, Unicode.Scalar?, Unicode.Scalar??, Substring)>
    do {
      // Assert the inferred capture type.
      typealias ExpectedMatch = (
        Substring, Unicode.Scalar?, Unicode.Scalar??, Substring
      )
      let _: ExpectedMatch.Type = type(of: regexWithCapture).RegexOutput.self
      let maybeMatchResult = line.wholeMatch(of: regexWithCapture)
      let matchResult = try XCTUnwrap(maybeMatchResult)
      let (wholeMatch, lower, upper, propertyString) = matchResult.output
      XCTAssertEqual(wholeMatch, Substring(line))
      XCTAssertEqual(lower, Unicode.Scalar(0xA6F0))
      XCTAssertEqual(upper, Unicode.Scalar(0xA6F1))
      XCTAssertEqual(propertyString, "Extend")
    }

    let regexWithTryCapture = Regex {
      TryCapture {
        OneOrMore(.hexDigit)
      } transform: {
        Unicode.Scalar(hex: $0)
      }
      Optionally {
        ".."
        TryCapture {
          OneOrMore(.hexDigit)
        } transform: {
          Unicode.Scalar(hex: $0)
        }
      }
      OneOrMore(.whitespace)
      ";"
      OneOrMore(.whitespace)
      Capture(OneOrMore(.word))
      ZeroOrMore(.any)
    } // Regex<(Substring, Unicode.Scalar, Unicode.Scalar?, Substring)>
    do {
      // Assert the inferred capture type.
      typealias ExpectedMatch = (
        Substring, Unicode.Scalar, Unicode.Scalar?, Substring
      )
      let _: ExpectedMatch.Type = type(of: regexWithTryCapture).RegexOutput.self
      let maybeMatchResult = line.wholeMatch(of: regexWithTryCapture)
      let matchResult = try XCTUnwrap(maybeMatchResult)
      let (wholeMatch, lower, upper, propertyString) = matchResult.output
      XCTAssertEqual(wholeMatch, Substring(line))
      XCTAssertEqual(lower, Unicode.Scalar(0xA6F0))
      XCTAssertEqual(upper, Unicode.Scalar(0xA6F1))
      XCTAssertEqual(propertyString, "Extend")
    }

    do {
      let regexLiteral = try Regex(
          #"([0-9A-F]+)(?:\.\.([0-9A-F]+))?\s+;\s+(\w+).*"#,
        as: (Substring, Substring, Substring?, Substring).self)
      let maybeMatchResult = line.wholeMatch(of: regexLiteral)
      let matchResult = try XCTUnwrap(maybeMatchResult)
      let (wholeMatch, lower, upper, propertyString) = matchResult.output
      XCTAssertEqual(wholeMatch, Substring(line))
      XCTAssertEqual(lower, "A6F0")
      XCTAssertEqual(upper, "A6F1")
      XCTAssertEqual(propertyString, "Extend")
    }
  }

  func testDynamicCaptures() throws {
    do {
      let regex = try Regex("aabcc.")
      let line = "aabccd"
      let match = try XCTUnwrap(line.wholeMatch(of: regex))
      XCTAssertEqual(match.0, line[...])
      let output = match.output
      XCTAssertEqual(output[0].substring, line[...])
    }
    do {
      let regex = try Regex(
          #"""
          (?<lower>[0-9A-F]+)(?:\.\.(?<upper>[0-9A-F]+))?\s+;\s+(?<desc>\w+).*
          """#)
      let line = """
        A6F0..A6F1    ; Extend # Mn   [2] BAMUM COMBINING MARK KOQNDON..BAMUM \
        COMBINING MARK TUKWENTIS
        """
      let match = try XCTUnwrap(line.wholeMatch(of: regex))
      XCTAssertEqual(match.0, line[...])
      let output = match.output
      XCTAssertEqual(output[0].substring, line[...])
      XCTAssertTrue(output[1].substring == "A6F0")
      XCTAssertTrue(output["lower"]?.substring == "A6F0")
      XCTAssertTrue(output[2].substring == "A6F1")
      XCTAssertTrue(output["upper"]?.substring == "A6F1")
      XCTAssertTrue(output[3].substring == "Extend")
      XCTAssertTrue(output["desc"]?.substring == "Extend")
      let typedOutput = try XCTUnwrap(output.as(
        (Substring, lower: Substring, upper: Substring?, Substring).self))
      XCTAssertEqual(typedOutput.0, line[...])
      XCTAssertTrue(typedOutput.lower == "A6F0")
      XCTAssertTrue(typedOutput.upper == "A6F1")
      XCTAssertTrue(typedOutput.3 == "Extend")
    }
  }

  func testBackreference() throws {
    try _testDSLCaptures(
      ("abc#41#42abcabcabc", ("abc#41#42abcabcabc", "abc", 42, "abc", nil)),
      matchType: (Substring, Substring, Int?, Substring?, Substring?).self, ==)
    {
      let a = Reference(Substring.self)
      let b = Reference(Int.self)
      Capture("abc", as: a)
      ZeroOrMore {
        TryCapture(as: b) {
          "#"
          OneOrMore(.digit)
        } transform: {
          Int($0.dropFirst())
        }
      }
      a
      ZeroOrMore {
        Capture(a)
      }
      Optionally {
        "b"
        Capture(a)
      }
    }

    // Match result referencing a `Reference`.
    do {
      let a = Reference(Substring.self)
      let b = Reference(Int.self)
      let regex = Regex {
        Capture("abc", as: a)
        ZeroOrMore {
          TryCapture(as: b) {
            "#"
            OneOrMore(.digit)
          } transform: {
            Int($0.dropFirst())
          }
        }
        a
        ZeroOrMore {
          Capture(b)
        }
        Optionally {
          Capture(a)
        }
      }
      let input = "abc#41#42abc#42#42"
      let result = try XCTUnwrap(input.wholeMatch(of: regex))
      XCTAssertEqual(result[a], "abc")
      XCTAssertEqual(result[b], 42)
    }

    // Post-hoc captured references
    // #"(?:\w\1|:(\w):)+"#
    try _testDSLCaptures(
      (":a:baca:o:boco", (":a:baca:o:boco", "o")),
      matchType: (Substring, Substring?).self,
      ==
    ) {
      // NOTE: "expression too complex to type check" when inferring the generic
      // parameter.
      OneOrMore {
        let a = Reference(Substring.self)
        ChoiceOf<(Substring, Substring?)> {
          Regex {
            .word
            a
          }
          Regex {
            ":"
            Capture(.word, as: a)
            ":"
          }
        }
      }
    }
  }
  
  func testSemanticVersionExample() {
    struct SemanticVersion: Equatable {
      var major: Int
      var minor: Int
      var patch: Int
      var dev: String?
    }
    struct SemanticVersionParser: CustomPrefixMatchRegexComponent {
      typealias RegexOutput = SemanticVersion
      func consuming(
        _ input: String,
        startingAt index: String.Index,
        in bounds: Range<String.Index>
      ) throws -> (upperBound: String.Index, output: SemanticVersion)? {
        let regex = Regex {
          TryCapture(OneOrMore(.digit)) { Int($0) }
          "."
          TryCapture(OneOrMore(.digit)) { Int($0) }
          Optionally {
            "."
            TryCapture(OneOrMore(.digit)) { Int($0) }
          }
          Optionally {
            "-"
            Capture(OneOrMore(.word))
          }
        }

        guard let match = input[index..<bounds.upperBound].firstMatch(of: regex),
              match.range.lowerBound == index
        else { return nil }

        let result = SemanticVersion(
          major: match.output.1,
          minor: match.output.2,
          patch: match.output.3 ?? 0,
          dev: match.output.4.map(String.init))
        return (match.range.upperBound, result)
      }
    }

    let versions = [
      ("1.0", SemanticVersion(major: 1, minor: 0, patch: 0)),
      ("1.0.1", SemanticVersion(major: 1, minor: 0, patch: 1)),
      ("12.100.5-dev", SemanticVersion(major: 12, minor: 100, patch: 5, dev: "dev")),
    ]

    let parser = SemanticVersionParser()
    for (str, version) in versions {
      XCTAssertEqual(str.wholeMatch(of: parser)?.output, version)
    }
  }
}

extension Unicode.Scalar {
  // Convert a hexadecimal string to a scalar
  init?<S: StringProtocol>(hex: S) {
    guard let val = UInt32(hex, radix: 16), let scalar = Self(val) else {
      return nil
    }
    self = scalar
  }
}

// MARK: Extra == functions

func == <T0: Equatable, T1: Equatable, T2: Equatable, T3: Equatable, T4: Equatable, T5: Equatable, T6: Equatable>(
  l: (T0, T1, T2, T3, T4, T5, T6), r: (T0, T1, T2, T3, T4, T5, T6)
) -> Bool {
  l.0 == r.0 && (l.1, l.2, l.3, l.4, l.5, l.6) == (r.1, r.2, r.3, r.4, r.5, r.6)
}
