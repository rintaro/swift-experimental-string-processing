import Exercises
import XCTest

//extension String: Error {}

let doPrint = false//true
func output<S: ExpressibleByStringInterpolation>(_ s: S) {
  if doPrint { print(s) }
}

class ExercisesTests: XCTestCase {
  func testAll() {

    // MARK: - Grapheme break properties
    output("Grapheme break properties")
    let reference = try! Exercises.referenceParticipant.graphemeBreakProperty()
    for participant in Exercises.allParticipants {
      let outputHeader = "  - \(participant.name): " // TODO: pad name...
      guard let f = try? participant.graphemeBreakProperty() else {
        output("\(outputHeader)unsupported")
        continue
      }

      var pass = true
      for line in graphemeBreakData.split(separator: "\n") {
        let line = String(line)
        let ref = reference(line)
        let result = f(line)
        guard ref == result else {
          pass = false
          XCTFail()
          break
        }
      }
      output("\(outputHeader)\(pass ? "pass" : "FAIL")")
    }

  }

}