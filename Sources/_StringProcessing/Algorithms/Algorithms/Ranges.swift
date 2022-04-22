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

// MARK: `RangesCollection`

struct RangesCollection<Searcher: CollectionSearcher> {
  public typealias Base = Searcher.Searched
  
  let base: Base
  let searcher: Searcher
  private(set) public var startIndex: Index

  init(base: Base, searcher: Searcher) {
    self.base = base
    self.searcher = searcher
    
    var state = searcher.state(for: base, in: base.startIndex..<base.endIndex)
    self.startIndex = Index(range: nil, state: state)

    if let range = searcher.search(base, &state) {
      self.startIndex = Index(range: range, state: state)
    } else {
      self.startIndex = endIndex
    }
  }
}

struct RangesIterator<Searcher: CollectionSearcher>: IteratorProtocol {
  public typealias Base = Searcher.Searched
  
  let base: Base
  let searcher: Searcher
  var state: Searcher.State

  init(base: Base, searcher: Searcher) {
    self.base = base
    self.searcher = searcher
    self.state = searcher.state(for: base, in: base.startIndex..<base.endIndex)
  }

  public mutating func next() -> Range<Base.Index>? {
    searcher.search(base, &state)
  }
}

extension RangesCollection: Sequence {
  public func makeIterator() -> RangesIterator<Searcher> {
    Iterator(base: base, searcher: searcher)
  }
}

extension RangesCollection: Collection {
  // TODO: Custom `SubSequence` for the sake of more efficient slice iteration
  
  public struct Index {
    var range: Range<Searcher.Searched.Index>?
    var state: Searcher.State
  }

  public var endIndex: Index {
    // TODO: Avoid calling `state(for:startingAt)` here
    Index(
      range: nil,
      state: searcher.state(for: base, in: base.startIndex..<base.endIndex))
  }

  public func formIndex(after index: inout Index) {
    guard index != endIndex else { fatalError("Cannot advance past endIndex") }
    index.range = searcher.search(base, &index.state)
  }

  public func index(after index: Index) -> Index {
    var index = index
    formIndex(after: &index)
    return index
  }

  public subscript(index: Index) -> Range<Base.Index> {
    guard let range = index.range else {
      fatalError("Cannot subscript using endIndex")
    }
    return range
  }
}

extension RangesCollection.Index: Comparable {
  static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs.range, rhs.range) {
    case (nil, nil):
      return true
    case (nil, _?), (_?, nil):
      return false
    case (let lhs?, let rhs?):
      return lhs.lowerBound == rhs.lowerBound
    }
  }

  static func < (lhs: Self, rhs: Self) -> Bool {
    switch (lhs.range, rhs.range) {
    case (nil, _):
      return false
    case (_, nil):
      return true
    case (let lhs?, let rhs?):
      return lhs.lowerBound < rhs.lowerBound
    }
  }
}

// MARK: `ReversedRangesCollection`

struct ReversedRangesCollection<Searcher: BackwardCollectionSearcher> {
  typealias Base = Searcher.BackwardSearched
  
  let base: Base
  let searcher: Searcher
  
  init(base: Base, searcher: Searcher) {
    self.base = base
    self.searcher = searcher
  }
}

extension ReversedRangesCollection: Sequence {
  public struct Iterator: IteratorProtocol {
    let base: Base
    let searcher: Searcher
    var state: Searcher.BackwardState
    
    init(base: Base, searcher: Searcher) {
      self.base = base
      self.searcher = searcher
      self.state = searcher.backwardState(
        for: base, in: base.startIndex..<base.endIndex)
    }
    
    public mutating func next() -> Range<Base.Index>? {
      searcher.searchBack(base, &state)
    }
  }
  
  public func makeIterator() -> Iterator {
    Iterator(base: base, searcher: searcher)
  }
}

// TODO: `Collection` conformance

// MARK: `CollectionSearcher` algorithms

extension Collection {
  func ranges<S: CollectionSearcher>(
    of searcher: S
  ) -> RangesCollection<S> where S.Searched == Self {
    RangesCollection(base: self, searcher: searcher)
  }
}

extension BidirectionalCollection {
  func rangesFromBack<S: BackwardCollectionSearcher>(
    of searcher: S
  ) -> ReversedRangesCollection<S> where S.BackwardSearched == Self {
    ReversedRangesCollection(base: self, searcher: searcher)
  }
}

// MARK: Fixed pattern algorithms

extension Collection where Element: Equatable {
  func ranges<S: Sequence>(
    of other: S
  ) -> RangesCollection<ZSearcher<Self>> where S.Element == Element {
    ranges(of: ZSearcher(pattern: Array(other), by: ==))
  }

  // FIXME: Return `some Collection<Range<Index>>` for SE-0346
  /// Finds and returns the ranges of the all occurrences of a given sequence
  /// within the collection.
  /// - Parameter other: The sequence to search for.
  /// - Returns: A collection of ranges of all occurrences of `other`. Returns
  ///  an empty collection if `other` is not found.
  @available(SwiftStdlib 5.7, *)
  public func ranges<S: Sequence>(
    of other: S
  ) -> [Range<Index>] where S.Element == Element {
    ranges(of: ZSearcher(pattern: Array(other), by: ==)).map { $0 }
  }
}

extension BidirectionalCollection where Element: Equatable {
  // FIXME
//  public func rangesFromBack<S: Sequence>(
//    of other: S
//  ) -> ReversedRangesCollection<ZSearcher<SubSequence>>
//    where S.Element == Element
//  {
//    fatalError()
//  }
}

extension BidirectionalCollection where Element: Comparable {
  func ranges<S: Sequence>(
    of other: S
  ) -> RangesCollection<PatternOrEmpty<TwoWaySearcher<Self>>>
    where S.Element == Element
  {
    ranges(of: PatternOrEmpty(searcher: TwoWaySearcher(pattern: Array(other))))
  }
  
  // FIXME
//  public func rangesFromBack<S: Sequence>(
//    of other: S
//  ) -> ReversedRangesCollection<PatternOrEmpty<TwoWaySearcher<SubSequence>>>
//    where S.Element == Element
//  {
//    rangesFromBack(
//      of: PatternOrEmpty(searcher: TwoWaySearcher(pattern: Array(other))))
//  }
}

// MARK: Regex algorithms

extension BidirectionalCollection where SubSequence == Substring {
  @available(SwiftStdlib 5.7, *)
  @_disfavoredOverload
  func ranges<R: RegexComponent>(
    of regex: R
  ) -> RangesCollection<RegexConsumer<R, Self>> {
    ranges(of: RegexConsumer(regex))
  }

  @available(SwiftStdlib 5.7, *)
  func rangesFromBack<R: RegexComponent>(
    of regex: R
  ) -> ReversedRangesCollection<RegexConsumer<R, Self>> {
    rangesFromBack(of: RegexConsumer(regex))
  }

  // FIXME: Return `some Collection<Range<Index>>` for SE-0346
  /// Finds and returns the ranges of the all occurrences of a given sequence
  /// within the collection.
  /// - Parameter regex: The regex to search for.
  /// - Returns: A collection or ranges in the receiver of all occurrences of
  /// `regex`. Returns an empty collection if `regex` is not found.
  @available(SwiftStdlib 5.7, *)
  public func ranges<R: RegexComponent>(
    of regex: R
  ) -> [Range<Index>] {
    Array(ranges(of: RegexConsumer(regex)))
  }
}
