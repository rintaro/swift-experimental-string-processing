import _StringProcessing

extension BenchmarkRunner {
  mutating func addHTML() {
    // Backreference + reluctant quantifier
    let r = #"<(\w*)\b[^>]*>(.*?)<\/\1>"#
    
    let html = CrossBenchmark(
      baseName: "html", regex: r, input: Inputs.swiftOrgHTML)
    html.register(&self)
  }
}
