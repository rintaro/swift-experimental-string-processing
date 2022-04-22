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

struct MEProgram<Input: Collection> where Input.Element: Equatable {
  typealias ConsumeFunction = (Input, Range<Input.Index>) -> Input.Index?
  typealias AssertionFunction =
    (Input, Input.Index, Range<Input.Index>) throws -> Bool
  typealias TransformFunction =
    (Input, Range<Input.Index>) throws -> Any?
  typealias MatcherFunction =
    (Input, Input.Index, Range<Input.Index>) throws -> (Input.Index, Any)?

  var instructions: InstructionList<Instruction>

  var staticElements: [Input.Element]
  var staticSequences: [[Input.Element]]
  var staticStrings: [String]
  var staticConsumeFunctions: [ConsumeFunction]
  var staticAssertionFunctions: [AssertionFunction]
  var staticTransformFunctions: [TransformFunction]
  var staticMatcherFunctions: [MatcherFunction]

  var registerInfo: RegisterInfo

  var enableTracing: Bool = false

  let captureStructure: CaptureStructure
  let referencedCaptureOffsets: [ReferenceID: Int]
  let namedCaptureOffsets: [String: Int]
}

extension MEProgram: CustomStringConvertible {
  var description: String {
    var result = """
    Elements: \(staticElements)
    Strings: \(staticStrings)

    """
    if !staticConsumeFunctions.isEmpty {
      result += "Consume functions: \(staticConsumeFunctions)"
    }

    // TODO: Extract into formatting code

    for idx in instructions.indices {
      let inst = instructions[idx]
      result += "[\(idx.rawValue)] \(inst)"
      if let sp = inst.stringRegister {
        result += " // \(staticStrings[sp.rawValue])"
      }
      if let ia = inst.instructionAddress {
        result += " // \(instructions[ia])"
      }
      result += "\n"
    }
    return result
  }
}
