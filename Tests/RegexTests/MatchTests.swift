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
@testable import _RegexParser
@testable import _StringProcessing

struct MatchError: Error {
    var message: String
    init(_ message: String) {
        self.message = message
    }
}

extension Executor {
  func _firstMatch(
    _ regex: String, input: String,
    syntax: SyntaxOptions = .traditional,
    enableTracing: Bool = false
  ) throws -> (match: Substring, captures: [Substring?]) {
    // TODO: This should be a CollectionMatcher API to call...
    // Consumer -> searcher algorithm
    var start = input.startIndex
    while true {
      if let result = try! self.dynamicMatch(
        input,
        in: start..<input.endIndex,
        .partialFromFront
      ) {
        let caps = result.rawCaptures.slices(from: input)
        return (input[result.range], caps)
      } else if start == input.endIndex {
        throw MatchError("match not found for \(regex) in \(input)")
      } else {
        input.formIndex(after: &start)
      }
    }
  }
}

func _firstMatch(
  _ regex: String,
  input: String,
  syntax: SyntaxOptions = .traditional,
  enableTracing: Bool = false
) throws -> (String, [String?]) {
  var executor = try _compileRegex(regex, syntax)
  executor.engine.enableTracing = enableTracing
  let (str, caps) = try executor._firstMatch(
    regex, input: input, enableTracing: enableTracing)
  let capStrs = caps.map { $0 == nil ? nil : String($0!) }
  return (String(str), capStrs)
}

// TODO: multiple-capture variant
// TODO: unify with firstMatch below, etc.
func flatCaptureTest(
  _ regex: String,
  _ tests: (input: String, expect: [String?]?)...,
  syntax: SyntaxOptions = .traditional,
  enableTracing: Bool = false,
  dumpAST: Bool = false,
  xfail: Bool = false,
  file: StaticString = #file,
  line: UInt = #line
) {
  for (test, expect) in tests {
    do {
      guard let (_, caps) = try? _firstMatch(
        regex,
        input: test,
        syntax: syntax,
        enableTracing: enableTracing
      ) else {
        if expect == nil {
          continue
        } else {
          throw MatchError("Match failed")
        }
      }
      guard let expect = expect else {
        throw MatchError("""
            Match of \(test) succeeded where failure expected in \(regex)
            """)
      }
      let capStrs = caps.map { $0 == nil ? nil : String($0!) }
      guard expect.count == capStrs.count else {
        throw MatchError("""
          Capture count mismatch:
            \(expect)
            \(capStrs)
          """)
      }

      guard expect.elementsEqual(capStrs) else {
        throw MatchError("""
          Capture mismatch:
            \(expect)
            \(capStrs)
          """)
      }
    } catch {
      if !xfail {
        XCTFail("\(error)", file: file, line: line)
      }
    }
  }
}

/// Test whether a string matches or not
///
/// TODO: Configuration for whole vs partial string matching...
func matchTest(
  _ regex: String,
  _ tests: (input: String, expect: Bool)...,
  syntax: SyntaxOptions = .traditional,
  enableTracing: Bool = false,
  dumpAST: Bool = false,
  xfail: Bool = false,
  file: StaticString = #file,
  line: UInt = #line
) {
  for (test, expect) in tests {
    firstMatchTest(
      regex,
      input: test,
      match: expect ? test : nil,
      syntax: syntax,
      enableTracing: enableTracing,
      dumpAST: dumpAST,
      xfail: xfail,
      file: file,
      line: line)
  }
}

// TODO: Adjust below to also check captures

/// Test the first match in a string, via `firstRange(of:)`
func firstMatchTest(
  _ regex: String,
  input: String,
  match: String?,
  syntax: SyntaxOptions = .traditional,
  enableTracing: Bool = false,
  dumpAST: Bool = false,
  xfail: Bool = false,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  do {
    let (found, _) = try _firstMatch(
      regex,
      input: input,
      syntax: syntax,
      enableTracing: enableTracing)

    if xfail {
      XCTAssertNotEqual(found, match, file: file, line: line)
    } else {
      XCTAssertEqual(found, match, file: file, line: line)
    }
  } catch {
    if !xfail && match != nil {
      XCTFail("\(error)", file: file, line: line)
    }
    return
  }
}

func firstMatchTests(
  _ regex: String,
  _ tests: (input: String, match: String?)...,
  syntax: SyntaxOptions = .traditional,
  enableTracing: Bool = false,
  dumpAST: Bool = false,
  xfail: Bool = false
) {
  for (input, match) in tests {
    firstMatchTest(
      regex,
      input: input,
      match: match,
      syntax: syntax,
      enableTracing: enableTracing,
      dumpAST: dumpAST,
      xfail: xfail)
  }
}

extension RegexTests {
  func testMatch() {
    firstMatchTest(
      "abc", input: "123abcxyz", match: "abc")
    firstMatchTest(
      #"abc\+d*"#, input: "123abc+xyz", match: "abc+")
    firstMatchTest(
      #"abc\+d*"#, input: "123abc+dddxyz", match: "abc+ddd")
    firstMatchTest(
      "a(b)", input: "123abcxyz", match: "ab")

    firstMatchTest(
      "(.)*(.*)", input: "123abcxyz", match: "123abcxyz")
    firstMatchTest(
      #"abc\d"#, input: "xyzabc123", match: "abc1")

    // MARK: Alternations

    firstMatchTest(
      "abc(?:de)+fghi*k|j", input: "123abcdefghijxyz", match: "j")
    firstMatchTest(
      "abc(?:de)+fghi*k|j", input: "123abcdedefghkxyz", match: "abcdedefghk")
    firstMatchTest(
      "a(?:b|c)?d", input: "123adxyz", match: "ad")
    firstMatchTest(
      "a(?:b|c)?d", input: "123abdxyz", match: "abd")
    firstMatchTest(
      "a(?:b|c)?d", input: "123acdxyz", match: "acd")
    firstMatchTest(
      "a?b??c+d+?e*f*?", input: "123abcdefxyz", match: "abcde")
    firstMatchTest(
      "a?b??c+d+?e*f*?", input: "123bcddefxyz", match: "bcd")
    firstMatchTest(
      "a|b?c", input: "123axyz", match: "a")
    firstMatchTest(
      "a|b?c", input: "123bcxyz", match: "bc")
    firstMatchTest(
      "(a|b)c", input: "123abcxyz", match: "bc")

    // Alternations with empty branches are permitted.
    firstMatchTest("|", input: "ab", match: "")
    firstMatchTest("(|)", input: "ab", match: "")
    firstMatchTest("a|", input: "ab", match: "a")
    firstMatchTest("a|", input: "ba", match: "")
    firstMatchTest("|b", input: "ab", match: "")
    firstMatchTest("|b", input: "ba", match: "")
    firstMatchTest("|b|", input: "ab", match: "")
    firstMatchTest("|b|", input: "ba", match: "")
    firstMatchTest("a|b|", input: "ab", match: "a")
    firstMatchTest("a|b|", input: "ba", match: "b")
    firstMatchTest("a|b|", input: "ca", match: "")
    firstMatchTest("||c|", input: "ab", match: "")
    firstMatchTest("||c|", input: "cb", match: "")
    firstMatchTest("|||", input: "ab", match: "")
    firstMatchTest("a|||d", input: "bc", match: "")
    firstMatchTest("a|||d", input: "abc", match: "a")
    firstMatchTest("a|||d", input: "d", match: "")

    // MARK: Unicode scalars

    firstMatchTest(
      #"a\u0065b\u{00000065}c\x65d\U00000065"#,
      input: "123aebecedexyz", match: "aebecede")

    firstMatchTest(
      #"\u{00000000000000000000000000A}"#,
      input: "123\nxyz", match: "\n")
    firstMatchTest(
      #"\x{00000000000000000000000000A}"#,
      input: "123\nxyz", match: "\n")
    firstMatchTest(
      #"\o{000000000000000000000000007}"#,
      input: "123\u{7}xyz", match: "\u{7}")

    firstMatchTest(#"\o{70}"#, input: "1238xyz", match: "8")
    firstMatchTest(#"\0"#, input: "123\0xyz", match: "\0")
    firstMatchTest(#"\01"#, input: "123\u{1}xyz", match: "\u{1}")
    firstMatchTest(#"\070"#, input: "1238xyz", match: "8")
    firstMatchTest(#"\07A"#, input: "123\u{7}Axyz", match: "\u{7}A")
    firstMatchTest(#"\08"#, input: "123\08xyz", match: "\08")
    firstMatchTest(#"\0707"#, input: "12387\u{1C7}xyz", match: "\u{1C7}")

    // code point sequence
    firstMatchTest(#"\u{61 62 63}"#, input: "123abcxyz", match: "abc", xfail: true)

    // Escape sequences that represent scalar values.
    firstMatchTest(#"\a[\b]\e\f\n\r\t"#,
                   input: "\u{7}\u{8}\u{1B}\u{C}\n\r\t",
                   match: "\u{7}\u{8}\u{1B}\u{C}\n\r\t")
    firstMatchTest(#"[\a][\b][\e][\f][\n][\r][\t]"#,
                   input: "\u{7}\u{8}\u{1B}\u{C}\n\r\t",
                   match: "\u{7}\u{8}\u{1B}\u{C}\n\r\t")

    firstMatchTest(#"\r\n"#, input: "\r\n", match: "\r\n")

    // MARK: Quotes

    firstMatchTest(
      #"a\Q .\Eb"#,
      input: "123a .bxyz", match: "a .b")
    firstMatchTest(
      #"a\Q \Q \\.\Eb"#,
      input: #"123a \Q \\.bxyz"#, match: #"a \Q \\.b"#)
    firstMatchTest(
      #"\d\Q...\E"#,
      input: "Countdown: 3... 2... 1...", match: "3...")

    // MARK: Comments

    firstMatchTest(
      #"a(?#comment)b"#, input: "123abcxyz", match: "ab")
    firstMatchTest(
      #"a(?#. comment)b"#, input: "123abcxyz", match: "ab")
  }

  func testMatchQuantification() {
    // MARK: Quantification

    firstMatchTest(
      #"a{1,2}"#, input: "123aaaxyz", match: "aa")
    firstMatchTest(
      #"a{,2}"#, input: "123aaaxyz", match: "")
    firstMatchTest(
      #"a{,2}x"#, input: "123aaaxyz", match: "aax")
    firstMatchTest(
      #"a{,2}x"#, input: "123xyz", match: "x")
    firstMatchTest(
      #"a{2,}"#, input: "123aaaxyz", match: "aaa")
    firstMatchTest(
      #"a{1}"#, input: "123aaaxyz", match: "a")
    firstMatchTest(
      #"a{1,2}?"#, input: "123aaaxyz", match: "a")
    firstMatchTest(
      #"a{1,2}?x"#, input: "123aaaxyz", match: "aax")
    firstMatchTest(
      #"xa{0}y"#, input: "123aaaxyz", match: "xy")
    firstMatchTest(
      #"xa{0,0}y"#, input: "123aaaxyz", match: "xy")
    firstMatchTest(
      #"(a|a){2}a"#, input: "123aaaxyz", match: "aaa")
    firstMatchTest(
      #"(a|a){3}a"#, input: "123aaaxyz", match: nil)

    firstMatchTest("a.*", input: "dcba", match: "a")

    firstMatchTest("a*", input: "", match: "")
    firstMatchTest("a*", input: "a", match: "a")
    firstMatchTest("a*", input: "aaa", match: "aaa")

    firstMatchTest("a*?", input: "", match: "")
    firstMatchTest("a*?", input: "a", match: "")
    firstMatchTest("a*?a", input: "aaa", match: "a")
    firstMatchTest("xa*?x", input: "_xx__", match: "xx")
    firstMatchTest("xa*?x", input: "_xax__", match: "xax")
    firstMatchTest("xa*?x", input: "_xaax__", match: "xaax")

    firstMatchTest("a+", input: "", match: nil)
    firstMatchTest("a+", input: "a", match: "a")
    firstMatchTest("a+", input: "aaa", match: "aaa")

    firstMatchTest("a+?", input: "", match: nil)
    firstMatchTest("a+?", input: "a", match: "a")
    firstMatchTest("a+?a", input: "aaa", match: "aa")
    firstMatchTest("xa+?x", input: "_xx__", match: nil)
    firstMatchTest("xa+?x", input: "_xax__", match: "xax")
    firstMatchTest("xa+?x", input: "_xaax__", match: "xaax")

    firstMatchTest("a??", input: "", match: "")
    firstMatchTest("a??", input: "a", match: "")
    firstMatchTest("a??a", input: "aaa", match: "a")
    firstMatchTest("xa??x", input: "_xx__", match: "xx")
    firstMatchTest("xa??x", input: "_xax__", match: "xax")
    firstMatchTest("xa??x", input: "_xaax__", match: nil)

    // Possessive .* will consume entire input
    firstMatchTests(
      ".*+x",
      ("abc", nil), ("abcx", nil), ("", nil))

    firstMatchTests(
      "a+b",
      ("abc", "ab"),
      ("aaabc", "aaab"),
      ("b", nil))
    firstMatchTests(
      "a++b",
      ("abc", "ab"),
      ("aaabc", "aaab"),
      ("b", nil))
    firstMatchTests(
      "a+?b",
      ("abc", "ab"),
      ("aaabc", "aaab"), // firstRange will match from front
      ("b", nil))

    firstMatchTests(
      "a+a",
      ("babc", nil),
      ("baaabc", "aaa"),
      ("bb", nil))
    firstMatchTests(
      "a++a",
      ("babc", nil),
      ("baaabc", nil),
      ("bb", nil))
    firstMatchTests(
      "a+?a",
      ("babc", nil),
      ("baaabc", "aa"),
      ("bb", nil))


    firstMatchTests(
      "a{2,4}a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", "aaa"),
      ("baaaaabc", "aaaaa"),
      ("baaaaaaaabc", "aaaaa"),
      ("bb", nil))
    firstMatchTests(
      "a{,4}a",
      ("babc", "a"),
      ("baabc", "aa"),
      ("baaabc", "aaa"),
      ("baaaaabc", "aaaaa"),
      ("baaaaaaaabc", "aaaaa"),
      ("bb", nil))
    firstMatchTests(
      "a{2,}a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", "aaa"),
      ("baaaaabc", "aaaaa"),
      ("baaaaaaaabc", "aaaaaaaa"),
      ("bb", nil))

    firstMatchTests(
      "a{2,4}?a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", "aaa"),
      ("baaaaabc", "aaa"),
      ("baaaaaaaabc", "aaa"),
      ("bb", nil))
    firstMatchTests(
      "a{,4}?a",
      ("babc", "a"),
      ("baabc", "a"),
      ("baaabc", "a"),
      ("baaaaabc", "a"),
      ("baaaaaaaabc", "a"),
      ("bb", nil))
    firstMatchTests(
      "a{2,}?a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", "aaa"),
      ("baaaaabc", "aaa"),
      ("baaaaaaaabc", "aaa"),
      ("bb", nil))

    firstMatchTests(
      "a{2,4}+a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", nil),
      ("baaaaabc", "aaaaa"),
      ("baaaaaaaabc", "aaaaa"),
      ("bb", nil))
    firstMatchTests(
      "a{,4}+a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", nil),
      ("baaaaabc", "aaaaa"),
      ("baaaaaaaabc", "aaaaa"),
      ("bb", nil))
    firstMatchTests(
      "a{2,}+a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", nil),
      ("baaaaabc", nil),
      ("baaaaaaaabc", nil),
      ("bb", nil))


    firstMatchTests(
      "(?:a{2,4}?b)+",
      ("aab", "aab"),
      ("aabaabaab", "aabaabaab"),
      ("aaabaaaabaabab", "aaabaaaabaab")
      // TODO: Nested reluctant reentrant example, xfailed
    )

    // Reluctant by default - '*/+/.' and '*?/+?/.?' are swapped
    firstMatchTest("(?U)a*", input: "aaa", match: "")
    firstMatchTest("(?U)a*a", input: "aaa", match: "a")
    firstMatchTest("(?U)a*?", input: "aaa", match: "aaa")
    firstMatchTest("(?U)a*?a", input: "aaa", match: "aaa")

    firstMatchTest("(?U)a+", input: "aaa", match: "a")
    firstMatchTest("(?U)a+?", input: "aaa", match: "aaa")

    firstMatchTest("(?U)a?", input: "a", match: "")
    firstMatchTest("(?U)a?a", input: "aaa", match: "a")
    firstMatchTest("(?U)a??", input: "a", match: "a")
    firstMatchTest("(?U)a??a", input: "aaa", match: "aa")

    // TODO: After captures, easier to test these
  }

  func testMatchCharacterClasses() {
    // MARK: Character classes

    firstMatchTest(#"abc\d"#, input: "xyzabc123", match: "abc1")

    firstMatchTest(
      "[-|$^:?+*())(*-+-]", input: "123(abc)xyz", match: "(")
    firstMatchTest(
      "[-|$^:?+*())(*-+-]", input: "123-abcxyz", match: "-")
    firstMatchTest(
      "[-|$^:?+*())(*-+-]", input: "123^abcxyz", match: "^")

    firstMatchTest(
      "[a-b-c]", input: "123abcxyz", match: "a")
    firstMatchTest(
      "[a-b-c]", input: "123-abcxyz", match: "-")

    firstMatchTest("[-a-]", input: "123abcxyz", match: "a")
    firstMatchTest("[-a-]", input: "123-abcxyz", match: "-")

    firstMatchTest("[a-z]", input: "123abcxyz", match: "a")
    firstMatchTest("[a-z]", input: "123ABCxyz", match: "x")
    firstMatchTest("[a-z]", input: "123-abcxyz", match: "a")

    // Character class subtraction
    firstMatchTest("[a-d--a-c]", input: "123abcdxyz", match: "d")

    firstMatchTest("[-]", input: "123-abcxyz", match: "-")

    // These are metacharacters in certain contexts, but normal characters
    // otherwise.
    firstMatchTest(":-]", input: "123:-]xyz", match: ":-]")

    firstMatchTest(
      "[^abc]", input: "123abcxyz", match: "1")
    firstMatchTest(
      "[a^]", input: "123abcxyz", match: "a")

    firstMatchTest(
      #"\D\S\W"#, input: "123ab-xyz", match: "ab-")

    firstMatchTest(
      #"[\dd]"#, input: "xyzabc123", match: "1")
    firstMatchTest(
      #"[\dd]"#, input: "xyzabcd123", match: "d")

    firstMatchTest(
      #"[^[\D]]"#, input: "xyzabc123", match: "1")
    firstMatchTest(
      "[[ab][bc]]", input: "123abcxyz", match: "a")
    firstMatchTest(
      "[[ab][bc]]", input: "123cbaxyz", match: "c")
    firstMatchTest(
      "[[ab]c[de]]", input: "123abcxyz", match: "a")
    firstMatchTest(
      "[[ab]c[de]]", input: "123cbaxyz", match: "c")

    firstMatchTest(
      #"[ab[:space:]\d[:^upper:]cd]"#,
      input: "123abcxyz", match: "1")
    firstMatchTest(
      #"[ab[:space:]\d[:^upper:]cd]"#,
      input: "xyzabc123", match: "x")
    firstMatchTest(
      #"[ab[:space:]\d[:^upper:]cd]"#,
      input: "XYZabc123", match: "a")
    firstMatchTest(
      #"[ab[:space:]\d[:^upper:]cd]"#,
      input: "XYZ abc123", match: " ")

    firstMatchTest("[[[:space:]]]", input: "123 abc xyz", match: " ")

    firstMatchTest("[[:alnum:]]", input: "[[:alnum:]]", match: "a")
    firstMatchTest("[[:blank:]]", input: "123\tabc xyz", match: "\t")

    firstMatchTest(
      "[[:graph:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")
    firstMatchTest(
      "[[:print:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: " ")

    firstMatchTest(
      "[[:word:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")
    firstMatchTest(
      "[[:xdigit:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")

    firstMatchTest("[[:isALNUM:]]", input: "[[:alnum:]]", match: "a")
    firstMatchTest("[[:AL_NUM:]]", input: "[[:alnum:]]", match: "a")

    firstMatchTest("[[:script=Greek:]]", input: "123αβγxyz", match: "α")

    func scalar(_ u: UnicodeScalar) -> UInt32 { u.value }

    for s in scalar("\u{C}") ... scalar("\u{1B}") {
      let u = UnicodeScalar(s)!
      firstMatchTest(#"[\f-\e]"#, input: "\u{B}\u{1C}\(u)", match: "\(u)")
    }
    for u: UnicodeScalar in ["\u{7}", "\u{8}"] {
      firstMatchTest(#"[\a-\b]"#, input: "\u{6}\u{9}\(u)", match: "\(u)")
    }
    for s in scalar("\u{A}") ... scalar("\u{D}") {
      let u = UnicodeScalar(s)!
      firstMatchTest(#"[\n-\r]"#, input: "\u{9}\u{E}\(u)", match: "\(u)")
    }
    firstMatchTest(#"[\t-\t]"#, input: "\u{8}\u{A}\u{9}", match: "\u{9}")

    // Currently not supported in the matching engine.
    for c: UnicodeScalar in ["a", "b", "c"] {
      firstMatchTest(#"[\c!-\C-#]"#, input: "def\(c)", match: "\(c)",
                     xfail: true)
    }
    for c: UnicodeScalar in ["$", "%", "&", "'"] {
      firstMatchTest(#"[\N{DOLLAR SIGN}-\N{APOSTROPHE}]"#,
                     input: "#()\(c)", match: "\(c)", xfail: true)
    }

    // MARK: Operators

    firstMatchTest(
      #"[a[bc]de&&[^bc]\d]+"#, input: "123bcdxyz", match: "d")

    // Empty intersection never matches, should this be a compile time error?
    // matchTest("[a&&b]", input: "123abcxyz", match: "")

    firstMatchTest(
      "[abc--def]", input: "123abcxyz", match: "a")

    // We left-associate for chained operators.
    firstMatchTest(
      "[ab&&b~~cd]", input: "123abcxyz", match: "b")
    firstMatchTest(
      "[ab&&b~~cd]", input: "123acdxyz", match: "c") // this doesn't match NSRegularExpression's behavior

    // Operators are only valid in custom character classes.
    firstMatchTest(
      "a&&b", input: "123a&&bcxyz", match: "a&&b")
    firstMatchTest(
      "&?", input: "123a&&bcxyz", match: "")
    firstMatchTest(
      "&&?", input: "123a&&bcxyz", match: "&&")
    firstMatchTest(
      "--+", input: "123---xyz", match: "---")
    firstMatchTest(
      "~~*", input: "123~~~xyz", match: "~~~")


    // Quotes in character classes.
    firstMatchTest(#"[\Qabc\E]"#, input: "QEa", match: "a")
    firstMatchTest(#"[\Qabc\E]"#, input: "cxx", match: "c")
    firstMatchTest(#"[\Qabc\E]+"#, input: "cba", match: "cba")
    firstMatchTest(#"[\Qa-c\E]+"#, input: "a-c", match: "a-c")

    firstMatchTest(#"["a-c"]+"#, input: "abc", match: "a",
                   syntax: .experimental)
    firstMatchTest(#"["abc"]+"#, input: "cba", match: "cba",
                   syntax: .experimental)
    firstMatchTest(#"["abc"]+"#, input: #""abc""#, match: "abc",
                   syntax: .experimental)
    firstMatchTest(#"["abc"]+"#, input: #""abc""#, match: #""abc""#)
  }

  func testCharacterProperties() {
    // MARK: Character names.

    firstMatchTest(#"\N{ASTERISK}"#, input: "123***xyz", match: "*")
    firstMatchTest(#"[\N{ASTERISK}]"#, input: "123***xyz", match: "*")
    firstMatchTest(
      #"\N{ASTERISK}+"#, input: "123***xyz", match: "***")
    firstMatchTest(
      #"\N {2}"#, input: "123  xyz", match: "3  ")

    firstMatchTest(#"\N{U+2C}"#, input: "123,xyz", match: ",")
    firstMatchTest(#"\N{U+1F4BF}"#, input: "123💿xyz", match: "💿")
    firstMatchTest(#"\N{U+00001F4BF}"#, input: "123💿xyz", match: "💿")

    // MARK: Character properties.

    firstMatchTest(#"\p{L}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(#"\p{gc=L}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(#"\p{Lu}"#, input: "123abcXYZ", match: "X")

    firstMatchTest(
      #"\P{Cc}"#, input: "\n\n\nXYZ", match: "X")
    firstMatchTest(
      #"\P{Z}"#, input: "   XYZ", match: "X")

    firstMatchTest(#"[\p{C}]"#, input: "123\n\n\nXYZ", match: "\n")
    firstMatchTest(#"\p{C}+"#, input: "123\n\n\nXYZ", match: "\n\n\n")

    // UAX44-LM3 means all of the below are equivalent.
    firstMatchTest(#"\p{ll}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(#"\p{gc=ll}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{General_Category=Ll}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{General-Category=isLl}"#,
      input: "123abcXYZ", match: "a")
    firstMatchTest(#"\p{  __l_ l  _ }"#, input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{ g_ c =-  __l_ l  _ }"#, input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{ general ca-tegory =  __l_ l  _ }"#,
      input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{- general category =  is__l_ l  _ }"#,
      input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{ general category -=  IS__l_ l  _ }"#,
      input: "123abcXYZ", match: "a")

    firstMatchTest(#"\p{Any}"#, input: "123abcXYZ", match: "1")
    firstMatchTest(#"\p{Assigned}"#, input: "123abcXYZ", match: "1")
    firstMatchTest(#"\p{ascii}"#, input: "123abcXYZ", match: "1")
    firstMatchTest(#"\p{isAny}"#, input: "123abcXYZ", match: "1")

    firstMatchTest(#"\p{sc=grek}"#, input: "123αβγxyz", match: "α")
    firstMatchTest(#"\p{sc=isGreek}"#, input: "123αβγxyz", match: "α")
    firstMatchTest(#"\p{Greek}"#, input: "123αβγxyz", match: "α")
    firstMatchTest(#"\p{isGreek}"#, input: "123αβγxyz", match: "α")
    firstMatchTest(#"\P{Script=Latn}"#, input: "abcαβγxyz", match: "α")
    firstMatchTest(#"\p{script=Greek}"#, input: "123αβγxyz", match: "α")
    firstMatchTest(#"\p{ISscript=isGreek}"#, input: "123αβγxyz", match: "α")
    firstMatchTest(#"\p{scx=bamum}"#, input: "123ꚠꚡꚢxyz", match: "ꚠ")
    firstMatchTest(#"\p{ISBAMUM}"#, input: "123ꚠꚡꚢxyz", match: "ꚠ")
    firstMatchTest(#"\p{Script=Unknown}"#, input: "\u{10FFFF}", match: "\u{10FFFF}")
    firstMatchTest(#"\p{scx=Gujr}"#, input: "\u{a839}", match: "\u{a839}")
    firstMatchTest(#"\p{Gujr}"#, input: "\u{a839}", match: "\u{a839}")

    firstMatchTest(#"\p{alpha}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(#"\P{alpha}"#, input: "123abcXYZ", match: "1")
    firstMatchTest(
      #"\p{alphabetic=True}"#, input: "123abcXYZ", match: "a")

    // This is actually available-ed...
    firstMatchTest(
      #"\p{emoji=t}"#, input: "123💿xyz", match: "a",
      xfail: true)

    firstMatchTest(#"\p{Alpha=no}"#, input: "123abcXYZ", match: "1")
    firstMatchTest(#"\P{Alpha=no}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(#"\p{isAlphabetic}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{isAlpha=isFalse}"#, input: "123abcXYZ", match: "1")

    // Oniguruma special support not in stdlib
    firstMatchTest(
      #"\p{In_Runic}"#, input: "123ᚠᚡᚢXYZ", match: "ᚠ",
    xfail: true)

    // TODO: PCRE special
    firstMatchTest(
      #"\p{Xan}"#, input: "[[:alnum:]]", match: "a",
      xfail: true)
    firstMatchTest(
      #"\p{Xps}"#, input: "123 abc xyz", match: " ",
      xfail: true)
    firstMatchTest(
      #"\p{Xsp}"#, input: "123 abc xyz", match: " ",
      xfail: true)
    firstMatchTest(
      #"\p{Xuc}"#, input: "$var", match: "$",
      xfail: true)
    firstMatchTest(
      #"\p{Xwd}"#, input: "[[:alnum:]]", match: "a",
      xfail: true)

    firstMatchTest(#"\p{alnum}"#, input: "[[:alnum:]]", match: "a")
    firstMatchTest(#"\p{is_alnum}"#, input: "[[:alnum:]]", match: "a")

    firstMatchTest(#"\p{blank}"#, input: "123\tabc xyz", match: "\t")
    firstMatchTest(
      #"\p{graph}"#,
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")

    firstMatchTest(
      #"\p{print}"#,
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: " ")
    firstMatchTest(
      #"\p{word}"#,
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")
    firstMatchTest(
      #"\p{xdigit}"#,
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")

    firstMatchTest("[[:alnum:]]", input: "[[:alnum:]]", match: "a")
    firstMatchTest("[[:blank:]]", input: "123\tabc xyz", match: "\t")
    firstMatchTest("[[:graph:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")
    firstMatchTest("[[:print:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: " ")
    firstMatchTest("[[:word:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")
    firstMatchTest("[[:xdigit:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")
  }

  func testAssertions() {
    // MARK: Assertions
    firstMatchTest(
      #"\d+(?= dollars)"#,
      input: "Price: 100 dollars", match: "100")
    firstMatchTest(
      #"\d+(?= pesos)"#,
      input: "Price: 100 dollars", match: nil)
    firstMatchTest(
      #"(?=\d+ dollars)\d+"#,
      input: "Price: 100 dollars", match: "100",
      xfail: true) // TODO

    firstMatchTest(
      #"\d+(*pla: dollars)"#,
      input: "Price: 100 dollars", match: "100")
    firstMatchTest(
      #"\d+(*positive_lookahead: dollars)"#,
      input: "Price: 100 dollars", match: "100")

    firstMatchTest(
      #"\d+(?! dollars)"#,
      input: "Price: 100 pesos", match: "100")
    firstMatchTest(
      #"\d+(?! dollars)"#,
      input: "Price: 100 dollars", match: "10")
    firstMatchTest(
      #"(?!\d+ dollars)\d+"#,
      input: "Price: 100 pesos", match: "100")
    firstMatchTest(
      #"\d+(*nla: dollars)"#,
      input: "Price: 100 pesos", match: "100")
    firstMatchTest(
      #"\d+(*negative_lookahead: dollars)"#,
      input: "Price: 100 pesos", match: "100")

    firstMatchTest(
      #"(?<=USD)\d+"#, input: "Price: USD100", match: "100", xfail: true)
    firstMatchTest(
      #"(*plb:USD)\d+"#, input: "Price: USD100", match: "100", xfail: true)
    firstMatchTest(
      #"(*positive_lookbehind:USD)\d+"#,
      input: "Price: USD100", match: "100", xfail: true)
    // engines generally enforce that lookbehinds are fixed width
    firstMatchTest(
      #"\d{3}(?<=USD\d{3})"#, input: "Price: USD100", match: "100", xfail: true)

    firstMatchTest(
      #"(?<!USD)\d+"#, input: "Price: JYP100", match: "100", xfail: true)
    firstMatchTest(
      #"(*nlb:USD)\d+"#, input: "Price: JYP100", match: "100", xfail: true)
    firstMatchTest(
      #"(*negative_lookbehind:USD)\d+"#,
      input: "Price: JYP100", match: "100", xfail: true)
    // engines generally enforce that lookbehinds are fixed width
    firstMatchTest(
      #"\d{3}(?<!USD\d{3})"#, input: "Price: JYP100", match: "100", xfail: true)
  }

  func testMatchAnchors() {
    // MARK: Anchors
    firstMatchTests(
      #"^\d+"#,
      ("123", "123"),
      (" 123", nil),
      ("123 456", "123"),
      (" 123 \n456", nil),
      (" \n123 \n456", nil))

    firstMatchTests(
      #"\d+$"#,
      ("123", "123"),
      (" 123", "123"),
      (" 123 \n456", "456"),
      (" 123\n456", "456"),
      ("123 456", "456"))

    firstMatchTests(
      #"\A\d+"#,
      ("123", "123"),
      (" 123", nil),
      (" 123 \n456", nil),
      (" 123\n456", nil),
      ("123 456", "123"))

    firstMatchTests(
      #"\d+\Z"#,
      ("123", "123"),
      (" 123", "123"),
      ("123\n", "123"),
      (" 123\n", "123"),
      (" 123 \n456", "456"),
      (" 123\n456", "456"),
      (" 123\n456\n", "456"),
      ("123 456", "456"))


    firstMatchTests(
      #"\d+\z"#,
      ("123", "123"),
      (" 123", "123"),
      ("123\n", nil),
      (" 123\n", nil),
      (" 123 \n456", "456"),
      (" 123\n456", "456"),
      (" 123\n456\n", nil),
      ("123 456", "456"))

    firstMatchTests(
      #"\d+\b"#,
      ("123", "123"),
      (" 123", "123"),
      ("123 456", "123"),
      ("123A 456", "456"))
    firstMatchTests(
      #"\d+\b\s\b\d+"#,
      ("123", nil),
      (" 123", nil),
      ("123 456", "123 456"))

    firstMatchTests(
      #"\B\d+"#,
      ("123", "23"),
      (" 123", "23"),
      ("123 456", "23"))

    // TODO: \G and \K

    // TODO: Oniguruma \y and \Y
    firstMatchTests(
      #"\u{65}"#,             // Scalar 'e' is present in both:
      ("Cafe\u{301}", "e"),   // composed and
      ("Sol Cafe", "e"))      // standalone
    firstMatchTests(
      #"\u{65}\y"#,           // Grapheme boundary assertion
      ("Cafe\u{301}", nil),
      ("Sol Cafe", "e"))
    firstMatchTests(
      #"\u{65}\Y"#,           // Grapheme non-boundary assertion
      ("Cafe\u{301}", "e"),
      ("Sol Cafe", nil))
  }

  func testMatchGroups() {
    // MARK: Groups

    // Named captures
    firstMatchTest(
      #"a(?<label>b)c"#, input: "123abcxyz", match: "abc")
    firstMatchTest(
      #"a(?'label'b)c"#, input: "123abcxyz", match: "abc")
    firstMatchTest(
      #"a(?P<label>b)c"#, input: "123abcxyz", match: "abc")

    // Other groups
    firstMatchTest(
      #"a(?:b)c"#, input: "123abcxyz", match: "abc")
    firstMatchTest(
      "(?|(a)|(b)|(c))", input: "123abcxyz", match: "a")

    firstMatchTest(
      #"(?:a|.b)c"#, input: "123abcacxyz", match: "abc")
    firstMatchTest(
      #"(?>a|.b)c"#, input: "123abcacxyz", match: "ac", xfail: true)
    firstMatchTest(
      "(*atomic:a|.b)c", input: "123abcacxyz", match: "ac", xfail: true)
    firstMatchTest(
      #"(?:a+)[a-z]c"#, input: "123aacacxyz", match: "aac")
    firstMatchTest(
      #"(?>a+)[a-z]c"#, input: "123aacacxyz", match: "ac", xfail: true)


    // TODO: Test example where non-atomic is significant
    firstMatchTest(
      #"\d+(?* dollars)"#,
      input: "Price: 100 dollars", match: "100", xfail: true)
    firstMatchTest(
      #"(?*\d+ dollars)\d+"#,
      input: "Price: 100 dollars", match: "100", xfail: true)
    firstMatchTest(
      #"\d+(*napla: dollars)"#,
      input: "Price: 100 dollars", match: "100", xfail: true)
    firstMatchTest(
      #"\d+(*non_atomic_positive_lookahead: dollars)"#,
      input: "Price: 100 dollars", match: "100", xfail: true)

    // TODO: Test example where non-atomic is significant
    firstMatchTest(
      #"(?<*USD)\d+"#, input: "Price: USD100", match: "100", xfail: true)
    firstMatchTest(
      #"(*naplb:USD)\d+"#, input: "Price: USD100", match: "100", xfail: true)
    firstMatchTest(
      #"(*non_atomic_positive_lookbehind:USD)\d+"#,
      input: "Price: USD100", match: "100", xfail: true)
    // engines generally enforce that lookbehinds are fixed width
    firstMatchTest(
      #"\d{3}(?<*USD\d{3})"#, input: "Price: USD100", match: "100", xfail: true)

    // https://www.effectiveperlprogramming.com/2019/03/match-only-the-same-unicode-script/
    firstMatchTest(
      #"abc(*sr:\d+)xyz"#, input: "abc۵۲۸528੫੨੮xyz", match: "۵۲۸", xfail: true)
    firstMatchTest(
      #"abc(*script_run:\d+)xyz"#,
      input: "abc۵۲۸528੫੨੮xyz", match: "۵۲۸", xfail: true)

    // TODO: Test example where atomic is significant
    firstMatchTest(
      #"abc(*asr:\d+)xyz"#, input: "abc۵۲۸528੫੨੮xyz", match: "۵۲۸", xfail: true)
    firstMatchTest(
      #"abc(*atomic_script_run:\d+)xyz"#,
      input: "abc۵۲۸528੫੨੮xyz", match: "۵۲۸", xfail: true)

  }

  func testMatchCaptureBehavior() {
    flatCaptureTest(
      #"a(b)c|abe"#,
      ("abc", ["b"]),
      ("abe", [nil]),
      ("axbe", nil))
    flatCaptureTest(
      #"a(bc)d|abce"#,
      ("abcd", ["bc"]),
      ("abce", [nil]),
      ("abxce", nil))
    flatCaptureTest(
      #"a(bc)+d|abce"#,
      ("abcbcbcd", ["bc"]),
      ("abcbce", nil),
      ("abce", [nil]),
      ("abcbbd", nil))
    flatCaptureTest(
      #"a(bc)+d|(a)bce"#,
      ("abcbcbcd", ["bc", nil]),
      ("abce", [nil, "a"]),
      ("abcbbd", nil))
    flatCaptureTest(
      #"a(b|c)+d|(a)bce"#,
      ("abcbcbcd", ["c", nil]),
      ("abce", [nil, "a"]),
      ("abcbbd", ["b", nil]))
    flatCaptureTest(
      #"a(b+|c+)d|(a)bce"#,
      ("abbbd", ["bbb", nil]),
      ("acccd", ["ccc", nil]),
      ("abce", [nil, "a"]),
      ("abbbe", nil),
      ("accce", nil),
      ("abcbbd", nil))
    flatCaptureTest(
      #"(?:\w\1|:(\w):)+"#,
      (":a:bacada", ["a"]),
      (":a:baca:o:boco", ["o"]),
      ("bacada", nil),
      (":a:boco", ["a"])          // this matches only the ':a:' prefix
    )
  }

  func testMatchReferences() {
    // TODO: Implement backreference/subpattern matching.
    firstMatchTest(
      #"(.)\1"#,
      input: "112", match: "11")
    firstMatchTest(
      #"(.)(.)(.)(.)(.)(.)(.)(.)(.)(.)\10"#,
      input: "aaaaaaaaabbc", match: "aaaaaaaaabb")

    firstMatchTest(
      #"(.)\g001"#,
      input: "112", match: "11")

    firstMatchTest(#"(.)(.)\g-02"#, input: "abac", match: "aba", xfail: true)
    firstMatchTest(#"(?<a>.)(.)\k<a>"#, input: "abac", match: "aba", xfail: true)
    firstMatchTest(#"\g'+2'(.)(.)"#, input: "abac", match: "aba", xfail: true)
  }
  
  func testMatchExamples() {
    // Backreferences
    matchTest(
      #"(sens|respons)e and \1ibility"#,
      ("sense and sensibility", true),
      ("response and responsibility", true),
      ("response and sensibility", false),
      ("sense and responsibility", false))
    matchTest(
      #"a(?'name'b(c))d\1\2|abce"#,
      ("abcdbcc", true),
      ("abcdbc", false),
      ("abce", true)
    )

    // Subpatterns
    matchTest(
      #"(sens|respons)e and (?1)ibility"#,
      ("sense and sensibility", true),
      ("response and responsibility", true),
      ("response and sensibility", true),
      ("sense and responsibility", true),
      xfail: true)

    // Palindromes
    matchTest(
      #"(\w)(?:(?R)|\w?)\1"#,
      ("abccba", true),
      ("abcba", true),
      ("abba", true),
      ("stackcats", true),
      ("racecar", true),
      ("a anna c", true), // OK: Partial match
      ("abc", false),
      ("cat", false),
      xfail: true
    )
    matchTest(
      #"^((\w)(?:(?1)|\w?)\2)$"#,
      ("abccba", true),
      ("abcba", true),
      ("abba", true),
      ("stackcats", true),
      ("racecar", true),
      ("a anna c", false), // FAIL: Not whole line
      ("abc", false),
      ("cat", false),
      xfail: true
    )

    // HTML tags
    matchTest(
      #"<([a-zA-Z][a-zA-Z0-9]*)\b[^>]*>.*?</\1>"#,
      ("<html> a b c </html>", true),
      (#"<table style="float:right"> a b c </table>"#, true),
      ("<html> a b c </htm>", false),
      ("<htm> a b c </html>", false),
      (#"<table style="float:right"> a b c </tab>"#, false)
    )

    // Doubled words
    flatCaptureTest(
      #"\b(\w+)\s+\1\b"#,
      ("this does have one one in it", ["one"]),
      ("pass me the the kettle", ["the"]),
      ("this doesn't have any", nil)
    )

    // Floats
    flatCaptureTest(
      #"^([-+])?([0-9]*)(?:\.([0-9]+))?(?:[eE]([-+]?[0-9]+))?$"#,
      ("123.45", [nil, "123", "45", nil]),
      ("-123e12", ["-", "123", nil, "12"]),
      ("+123.456E-12", ["+", "123", "456", "-12"]),
      ("-123e1.2", nil)
    )
  }
  
  func testSingleLineMode() {
    firstMatchTest(#".+"#, input: "a\nb", match: "a")
    firstMatchTest(#"(?s:.+)"#, input: "a\nb", match: "a\nb")
  }
  
  func testCaseSensitivity() {
    matchTest(
      #"c..e"#,
      ("cafe", true),
      ("Cafe", false))
    matchTest(
      #"(?i)c.f."#,
      ("cafe", true),
      ("Cafe", true),
      ("caFe", true))
    matchTest(
      #"(?i)cafe"#,
      ("cafe", true),
      ("Cafe", true),
      ("caFe", true))
    matchTest(
      #"(?i)café"#,
      ("café", true),
      ("CafÉ", true))
    matchTest(
      #"(?i)\u{63}af\u{e9}"#,
      ("café", true),
      ("CafÉ", true))
    
    matchTest(
      #"[caFE]{4}"#,
      ("cafe", false),
      ("CAFE", false),
      ("caFE", true),
      ("EFac", true))
    matchTest(
      #"(?i)[caFE]{4}"#,
      ("cafe", true),
      ("CaFe", true),
      ("EfAc", true))
    matchTest(
      #"(?i)[a-f]{4}"#,
      ("cafe", true),
      ("CaFe", true),
      ("EfAc", true))
  }

  func testNonSemanticWhitespace() {
    firstMatchTest(#" \t "#, input: " \t ", match: " \t ")
    firstMatchTest(#"(?xx) \t "#, input: " \t ", match: "\t")

    firstMatchTest(#"[ \t]+"#, input: " \t ", match: " \t ")
    firstMatchTest(#"(?xx)[ \t]+"#, input: " \t ", match: "\t")
    firstMatchTest(#"(?xx)[ \t]+"#, input: " \t\t ", match: "\t\t")
    firstMatchTest(#"(?xx)[ \t]+"#, input: " \t \t", match: "\t")

    firstMatchTest("(?xx)[ a && ab ]+", input: " aaba ", match: "aa")
    firstMatchTest("(?xx)[ ] a ]+", input: " a]]a ] ", match: "a]]a")
  }
  
  func testASCIIClasses() {
    // 'D' ASCII-only digits
    matchTest(
      #"\d+"#,
      ("123", true),
      ("¹೨¾", true))
    matchTest(
      #"(?D)\d+"#,
      ("123", true),
      ("¹೨¾", false))
    matchTest(
      #"(?P)\d+"#,
      ("123", true),
      ("¹೨¾", false))

    // 'W' ASCII-only word characters (and word boundaries)
    matchTest(
      #"\w+"#,
      ("aeiou", true),
      ("åe\u{301}ïôú", true))
    matchTest(
      #"(?W)\w+"#,
      ("aeiou", true),
      ("åe\u{301}ïôú", false))
    matchTest(
      #"(?P)\w+"#,
      ("aeiou", true),
      ("åe\u{301}ïôú", false))

    matchTest(
      #"abcd\b.+"#,
      ("abcd ef", true),
      ("abcdef", false),
      ("abcdéf", false))
    matchTest(
      #"(?W)abcd\b.+"#,
      ("abcd ef", true),
      ("abcdef", false),
      ("abcdéf", true)) // "dé" matches /d\b./ because "é" isn't ASCII
    matchTest(
      #"(?P)abcd\b.+"#,
      ("abcd ef", true),
      ("abcdef", false),
      ("abcdéf", true)) // "dé" matches /d\b./ because "é" isn't ASCII

    // 'S' ASCII-only spaces
    matchTest(
      #"a\sb"#,
      ("a\tb", true),
      ("a\u{202f}b", true)) // NARROW NO-BREAK SPACE
    matchTest(
      #"(?S)a\sb"#,
      ("a\tb", true),
      ("a\u{202f}b", false))
    matchTest(
      #"(?P)a\sb"#,
      ("a\tb", true),
      ("a\u{202f}b", false))
  }
  
  func testAnchorMatching() throws {
    let string = """
      01: Alabama
      02: Alaska
      03: Arizona
      04: Arkansas
      05: California
      """
    XCTAssertTrue(string.contains(try Regex(#"^\d+"#)))
    XCTAssertEqual(string.ranges(of: try Regex(#"^\d+"#)).count, 1)
    XCTAssertEqual(string.ranges(of: try Regex(#"(?m)^\d+"#)).count, 5)

    let regex = try Regex(#"^\d+: [\w ]+$"#)
    XCTAssertFalse(string.contains(regex))
    let allRanges = string.ranges(of: regex.anchorsMatchLineEndings())
    XCTAssertEqual(allRanges.count, 5)
  }
  
  func testMatchingOptionsScope() {
    // `.` only matches newlines when the 's' option (single-line mode)
    // is turned on. Standalone option-setting groups (e.g. `(?s)`) are
    // scoped only to the current group.
    
    firstMatchTest(#"(?s)a.b"#, input: "a\nb", match: "a\nb")
    firstMatchTest(#"((?s)a.)b"#, input: "a\nb", match: "a\nb")
    firstMatchTest(#"(?-s)((?s)a.)b"#, input: "a\nb", match: "a\nb")
    firstMatchTest(#"(?-s)(?s:a.)b"#, input: "a\nb", match: "a\nb")
    firstMatchTest(#"((?s)a).b"#, input: "a\nb", match: nil)
    firstMatchTest(#"((?s))a.b"#, input: "a\nb", match: nil)
    firstMatchTest(#"(?:(?s))a.b"#, input: "a\nb", match: nil)
    firstMatchTest(#"((?s)a(?s)).b"#, input: "a\nb", match: nil)
    firstMatchTest(#"(?s)a(?-s).b"#, input: "a\nb", match: nil)
    firstMatchTest(#"(?s)a(?-s:.b)"#, input: "a\nb", match: nil)
    firstMatchTest(#"(?:(?s)a).b"#, input: "a\nb", match: nil)
    firstMatchTest(#"(((?s)a)).b"#, input: "a\nb", match: nil)
    firstMatchTest(#"(?s)(((?-s)a)).b"#, input: "a\nb", match: "a\nb")
    firstMatchTest(#"(?s)((?-s)((?i)a)).b"#, input: "a\nb", match: "a\nb")

    // Matching option changing persists across alternations.
    firstMatchTest(#"a(?s)b|c|.d"#, input: "abc", match: "ab")
    firstMatchTest(#"a(?s)b|c|.d"#, input: "c", match: "c")
    firstMatchTest(#"a(?s)b|c|.d"#, input: "a\nd", match: "\nd")
    firstMatchTest(#"a(?s)(?^)b|c|.d"#, input: "a\nd", match: nil)
    firstMatchTest(#"a(?s)b|.c(?-s)|.d"#, input: "a\nd", match: nil)
    firstMatchTest(#"a(?s)b|.c(?-s)|.d"#, input: "a\nc", match: "\nc")
    firstMatchTest(#"a(?s)b|c(?-s)|(?^s).d"#, input: "a\nd", match: "\nd")
    firstMatchTest(#"a(?:(?s).b)|.c|.d"#, input: "a\nb", match: "a\nb")
    firstMatchTest(#"a(?:(?s).b)|.c"#, input: "a\nc", match: nil)
  }
  
  func testOptionMethods() throws {
    let regex = try Regex("c.f.")
    XCTAssertTrue ("cafe".contains(regex))
    XCTAssertFalse("CaFe".contains(regex))
    
    let caseInsensitiveRegex = regex.ignoresCase()
    XCTAssertTrue("cafe".contains(caseInsensitiveRegex))
    XCTAssertTrue("CaFe".contains(caseInsensitiveRegex))
  }
  
  // MARK: Character Semantics
  
  var eComposed: String { "é" }
  var eDecomposed: String { "e\u{301}" }
  
  func testIndividualScalars() {
    // Expectation: A standalone Unicode scalar value in a regex literal
    // can match either that specific scalar value or participate in matching
    // as a character.

    firstMatchTest(#"\u{65}\u{301}$"#, input: eDecomposed, match: eDecomposed)
    // FIXME: Decomposed character in regex literal doesn't match an equivalent character
    firstMatchTest(#"\u{65}\u{301}$"#, input: eComposed, match: eComposed,
      xfail: true)

    firstMatchTest(#"\u{65}"#, input: eDecomposed, match: "e")
    firstMatchTest(#"\u{65}$"#, input: eDecomposed, match: nil)
    // FIXME: \y is unsupported
    firstMatchTest(#"\u{65}\y"#, input: eDecomposed, match: nil,
      xfail: true)

    // FIXME: Unicode scalars are only matched at the start of a grapheme cluster
    firstMatchTest(#"\u{301}"#, input: eDecomposed, match: "\u{301}",
      xfail: true)
    // FIXME: \y is unsupported
    firstMatchTest(#"\y\u{301}"#, input: eDecomposed, match: nil,
      xfail: true)
  }

  func testCanonicalEquivalence() throws {
    // Expectation: Matching should use canonical equivalence whenever comparing
    // characters, so a user can write characters using any equivalent spelling
    // in either a regex literal or the string targeted for matching.
    
    matchTest(
      #"é$"#,
      (eComposed, true),
      (eDecomposed, true))

    // FIXME: Decomposed character in regex literal doesn't match an equivalent character
    matchTest(
      #"e\u{301}$"#,
      (eComposed, true),
      (eDecomposed, true),
      xfail: true)

    matchTest(
      #"e$"#,
      (eComposed, false),
      (eDecomposed, false))
  }

  func testCanonicalEquivalenceCharacterClass() throws {
    // Expectation: Character classes should match equivalent characters to the
    // same degree, regardless of how they are spelled. Unicode "property
    // classes" should match characters when all the code points that comprise
    // the character are members of the property class.
    
    // \w
    matchTest(
      #"^\w$"#,
      (eComposed, true),
      (eDecomposed, true))
    // \p{Letter}
    firstMatchTest(#"\p{Letter}$"#, input: eComposed, match: eComposed)
    // FIXME: \p{Letter} doesn't match a decomposed character
    firstMatchTest(#"\p{Letter}$"#, input: eDecomposed, match: eDecomposed,
              xfail: true)
    
    // \d
    firstMatchTest(#"\d"#, input: "5", match: "5")
    // FIXME: \d shouldn't match a digit composed with a non-digit character
    firstMatchTest(#"\d"#, input: "5\u{305}", match: nil,
              xfail: true)
    // \p{Number}
    firstMatchTest(#"\p{Number}"#, input: "5", match: "5")
    // FIXME: \p{Number} shouldn't match a number composed with a non-number character
    firstMatchTest(#"\p{Number}"#, input: "5\u{305}", match: nil,
              xfail: true)
    
    // Should this match the '5' but not the ZWJ, or should it treat '5'+ZWJ
    // as one entity and fail to match altogether?
    firstMatchTest(#"^\d"#, input: "5\u{200d}0", match: "5",
              xfail: true)
    
    // \s
    firstMatchTest(#"\s"#, input: " ", match: " ")
    // FIXME: \s shouldn't match a number composed with a non-number character
    firstMatchTest(#"\s\u{305}"#, input: " ", match: nil,
              xfail: true)
    // \p{Whitespace}
    firstMatchTest(#"\s"#, input: " ", match: " ")
    // FIXME: \p{Whitespace} shouldn't match whitespace composed with a non-whitespace character
    firstMatchTest(#"\s\u{305}"#, input: " ", match: nil,
              xfail: true)
  }
  
  func testCanonicalEquivalenceCustomCharacterClass() throws {
    // Expectation: Concatenations with custom character classes should be able
    // to match within a grapheme cluster. That is, a regex should be able to
    // match the scalar values that comprise a grapheme cluster in separate,
    // or repeated, custom character classes.
    
    matchTest(
      #"[áéíóú]$"#,
      (eComposed, true),
      (eDecomposed, true))

    // FIXME: Custom char classes don't use canonical equivalence with composed characters
    firstMatchTest(#"e[\u{301}]$"#, input: eComposed, match: eComposed,
              xfail: true)
    firstMatchTest(#"e[\u{300}-\u{320}]$"#, input: eComposed, match: eComposed,
              xfail: true)
    firstMatchTest(#"[a-z][\u{300}-\u{320}]$"#, input: eComposed, match: eComposed,
              xfail: true)

    // FIXME: Custom char classes don't match decomposed characters
    firstMatchTest(#"e[\u{301}]$"#, input: eDecomposed, match: eDecomposed,
              xfail: true)
    firstMatchTest(#"e[\u{300}-\u{320}]$"#, input: eDecomposed, match: eDecomposed,
              xfail: true)
    firstMatchTest(#"[a-z][\u{300}-\u{320}]$"#, input: eDecomposed, match: eDecomposed,
              xfail: true)

    let flag = "🇰🇷"
    firstMatchTest(#"🇰🇷"#, input: flag, match: flag)
    firstMatchTest(#"[🇰🇷]"#, input: flag, match: flag)
    firstMatchTest(#"\u{1F1F0}\u{1F1F7}"#, input: flag, match: flag)
    
    // First Unicode scalar followed by CCC of regional indicators
    firstMatchTest(#"\u{1F1F0}[\u{1F1E6}-\u{1F1FF}]"#, input: flag, match: flag)

    // FIXME: CCC of Regional Indicator doesn't match with both parts of a flag character
    // A CCC of regional indicators x 2
    firstMatchTest(#"[\u{1F1E6}-\u{1F1FF}]{2}"#, input: flag, match: flag,
              xfail: true)

    // FIXME: A single CCC of regional indicators matches the whole flag character
    // A CCC of regional indicators followed by the second Unicode scalar
    firstMatchTest(#"[\u{1F1E6}-\u{1F1FF}]\u{1F1F7}"#, input: flag, match: flag,
              xfail: true)
    // A single CCC of regional indicators
    firstMatchTest(#"[\u{1F1E6}-\u{1F1FF}]"#, input: flag, match: nil,
              xfail: true)
    
    // A single CCC of actual flag emojis / combined regional indicators
    firstMatchTest(#"[🇦🇫-🇿🇼]"#, input: flag, match: flag)
    // This succeeds (correctly) because \u{1F1F0} is lexicographically
    // within the CCC range
    firstMatchTest(#"[🇦🇫-🇿🇼]"#, input: "\u{1F1F0}abc", match: "\u{1F1F0}")
  }
  
  func testAnyChar() throws {
    // Expectation: \X and, in grapheme cluster mode, `.` should consume an
    // entire character, regardless of how it's spelled. \O should consume only
    // a single Unicode scalar value, leaving any other grapheme scalar
    // components to be matched.
    
    firstMatchTest(#"(?u:.)"#, input: eDecomposed, match: "e")

    matchTest(
      #".\u{301}"#,
      (eComposed, false),
      (eDecomposed, false))
    matchTest(
      #"\X\u{301}"#,
      (eComposed, false),
      (eDecomposed, false))
    
    // FIXME: \O is unsupported
    firstMatchTest(#"(?u)\O\u{301}"#, input: eDecomposed, match: eDecomposed)
    firstMatchTest(#"(?u)e\O"#, input: eDecomposed, match: eDecomposed,
      xfail: true)
    firstMatchTest(#"\O"#, input: eComposed, match: eComposed)
    firstMatchTest(#"\O"#, input: eDecomposed, match: nil,
              xfail: true)

    matchTest(
      #"(?u).\u{301}"#,
      (eComposed, false),
      (eDecomposed, true))
    firstMatchTest(#"(?u).$"#, input: eComposed, match: eComposed)
    
    // Option permutations for 'u' and 's'
    matchTest(
      #"...."#,
      ("e\u{301}ab", false),
      ("e\u{301}abc", true),
      ("e\u{301}\nab", false))
    matchTest(
      #"(?s)...."#,
      ("e\u{301}ab", false),
      ("e\u{301}abc", true),
      ("e\u{301}\nab", true))
    matchTest(
      #"(?u)...."#,
      ("e\u{301}ab", true),
      ("e\u{301}\na", false))
    matchTest(
      #"(?us)...."#,
      ("e\u{301}ab", true),
      ("e\u{301}\na", true))
  }
  
  // TODO: Add test for implied grapheme cluster requirement at group boundaries
  
  // TODO: Add test for grapheme boundaries at start/end of match
}

