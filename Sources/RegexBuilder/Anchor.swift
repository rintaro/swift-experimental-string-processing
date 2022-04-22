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

@_implementationOnly import _RegexParser
@_spi(RegexBuilder) import _StringProcessing

@available(SwiftStdlib 5.7, *)
public struct Anchor {
  internal enum Kind {
    case startOfSubject
    case endOfSubjectBeforeNewline
    case endOfSubject
    case firstMatchingPositionInSubject
    case textSegmentBoundary
    case startOfLine
    case endOfLine
    case wordBoundary
  }
  
  var kind: Kind
  var isInverted: Bool = false
}

@available(SwiftStdlib 5.7, *)
extension Anchor: RegexComponent {
  var baseAssertion: DSLTree._AST.AssertionKind {
    switch kind {
    case .startOfSubject: return .startOfSubject(isInverted)
    case .endOfSubjectBeforeNewline: return .endOfSubjectBeforeNewline(isInverted)
    case .endOfSubject: return .endOfSubject(isInverted)
    case .firstMatchingPositionInSubject: return .firstMatchingPositionInSubject(isInverted)
    case .textSegmentBoundary: return .textSegmentBoundary(isInverted)
    case .startOfLine: return .startOfLine(isInverted)
    case .endOfLine: return .endOfLine(isInverted)
    case .wordBoundary: return .wordBoundary(isInverted)
    }
  }
  
  public var regex: Regex<Substring> {
    Regex(node: .atom(.assertion(baseAssertion)))
  }
}

// MARK: - Public API

@available(SwiftStdlib 5.7, *)
extension Anchor {
  public static var startOfSubject: Anchor {
    Anchor(kind: .startOfSubject)
  }

  public static var endOfSubjectBeforeNewline: Anchor {
    Anchor(kind: .endOfSubjectBeforeNewline)
  }

  public static var endOfSubject: Anchor {
    Anchor(kind: .endOfSubject)
  }

  // TODO: Are we supporting this?
//  public static var resetStartOfMatch: Anchor {
//    Anchor(kind: resetStartOfMatch)
//  }

  public static var firstMatchingPositionInSubject: Anchor {
    Anchor(kind: .firstMatchingPositionInSubject)
  }

  public static var textSegmentBoundary: Anchor {
    Anchor(kind: .textSegmentBoundary)
  }
  
  public static var startOfLine: Anchor {
    Anchor(kind: .startOfLine)
  }

  public static var endOfLine: Anchor {
    Anchor(kind: .endOfLine)
  }

  public static var wordBoundary: Anchor {
    Anchor(kind: .wordBoundary)
  }
  
  public var inverted: Anchor {
    var result = self
    result.isInverted.toggle()
    return result
  }
}

@available(SwiftStdlib 5.7, *)
public struct Lookahead<Output>: _BuiltinRegexComponent {
  public var regex: Regex<Output>

  init(_ regex: Regex<Output>) {
    self.regex = regex
  }

  public init<R: RegexComponent>(
    _ component: R,
    negative: Bool = false
  ) where R.RegexOutput == Output {
    self.init(node: .nonCapturingGroup(
      negative ? .negativeLookahead : .lookahead, component.regex.root))
  }

  public init<R: RegexComponent>(
    negative: Bool = false,
    @RegexComponentBuilder _ component: () -> R
  ) where R.RegexOutput == Output {
    self.init(node: .nonCapturingGroup(
      negative ? .negativeLookahead : .lookahead, component().regex.root))
  }
}
