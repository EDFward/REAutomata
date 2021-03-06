#!/usr/bin/swift

import Foundation

// Labeled edge in automata.
struct Edge {

  enum EdgeType {
    case Epsilon
    case Normal(Character)
  }

  let type: EdgeType
  let dest: State

  init(_ type: EdgeType, dest: State) {
    self.type = type
    self.dest = dest
  }
}


class State: Hashable, Equatable {

  private var neighbors: [Edge] = [Edge]()

  func addEdge(edge: Edge) {
    neighbors.append(edge)
  }

  func getClosure() -> Set<State> {
    var closure: Set<State> = [self]
    // DFS with a stack.
    var stack: [State] = [self]
    while !stack.isEmpty {
      let poppedState = stack.removeLast()
      poppedState.neighbors
        .forEach({ edge in
          switch edge.type {
          case .Epsilon where !closure.contains(edge.dest):
            closure.insert(edge.dest)
            stack.append(edge.dest)
          default: break
          }
        })
    }
    return closure
  }

  // NFA stepping.
  func step(ch: Character) -> Set<State> {
    var nextStates = Set<State>()
    for state in getClosure() {
      state.neighbors
        .forEach({ edge in
          switch edge.type {
          case .Normal(ch):
            nextStates.insert(edge.dest)
          default: break
          }
        })
    }
    return nextStates
  }

  // DFA stepping.
  func step(ch: Character) -> State? {
    guard let index = neighbors.indexOf({ edge in
      switch edge.type {
      case .Normal(ch): return true
      default: return false
      }
    }) else {
      return nil
    }

    return neighbors[index].dest
  }

  var hashValue: Int {
    get {
      return ObjectIdentifier(self).hashValue
    }
  }
}

func ==(lhs: State, rhs: State) -> Bool {
  return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
}

/// Concatenation of two ϵ-NFAs, with respective start states and terminal states.
/// Return new start state and terminal state.
/// [Concat Image](https://en.wikipedia.org/wiki/File:Thompson-concat.svg)
func concat(automaton: (State, State), with anotherAutomaton: (State, State)) -> (State, State) {
  let (start1, terminal1) = automaton
  let (start2, terminal2) = anotherAutomaton
  terminal1.addEdge(Edge(.Epsilon, dest: start2))
  return (start1, terminal2)
}

/// Union of two ϵ-NFAs, similar to `concat`.
/// [Union Image](https://en.wikipedia.org/wiki/File:Thompson-or.svg)
func union(automaton: (State, State), with anotherAutomaton: (State, State)) -> (State, State) {
  let (start1, terminal1) = automaton
  let (start2, terminal2) = anotherAutomaton
  let newStart = State()
  let newTerminal = State()
  newStart.addEdge(Edge(.Epsilon, dest: start1))
  newStart.addEdge(Edge(.Epsilon, dest: start2))
  terminal1.addEdge(Edge(.Epsilon, dest: newTerminal))
  terminal2.addEdge(Edge(.Epsilon, dest: newTerminal))
  return (newStart, newTerminal)
}

/// Closure of a ϵ-NFA by Kleene star, parameters and return arguments are similar to `concat` and `union`.
/// [Closure Image](https://en.wikipedia.org/wiki/File:Thompson-kleene-star.svg)
func closure(automaton: (State, State)) -> (State, State) {
  let (start, terminal) = automaton
  let newStart = State()
  let newTerminal = State()
  newStart.addEdge(Edge(.Epsilon, dest: start))
  newStart.addEdge(Edge(.Epsilon, dest: newTerminal))
  terminal.addEdge(Edge(.Epsilon, dest: start))
  terminal.addEdge(Edge(.Epsilon, dest: newTerminal))
  return (newStart, newTerminal)
}

func balancedBrackets(characters: [Character]) -> Dictionary<Int, Int> {
  var matchingBrackets = Dictionary<Int, Int>()
  var start = 0, end = characters.count - 1
  while start < end {
    while start < end && characters[start] != "(" {
      start++
    }
    while end > start && characters[end] != ")" {
      end--
    }
    if start < end {
      matchingBrackets[start] = end
      start++
      end--
    }
  }
  return matchingBrackets
}

/// Regular Expressions to recognize binary string patterns.
/// NFA is built in [Thompson's construction](https://en.wikipedia.org/wiki/Thompson%27s_construction),
/// and could optionally convert to DFA if specified.
/// Only "0, 1, |, *, (, )" can be used.
public class REAutomata {

  // Start and terminal NFA states.
  let nfa: (start: State, terminal: State)

  // Optional DFA. Used only when `compileToDFA` flag is set for contruction.
  var dfa: (start: State, terminals: Set<State>)?

  // Assume expressions always valid.
  init(expr: String, compileToDFA: Bool = false) {
    let characters = [Character](expr.characters)
    // Calculate positions of balanced brackets.
    var matchingBrackets = balancedBrackets(characters)

    // Recursive lambda by hacks: http://rosettacode.org/wiki/Anonymous_recursion#Swift
    let parse: (Int, Int) -> (State, State) = {
      // An adhoc / ugly / naive way of parsing.
      func parseHelper(startIndex: Int, _ endIndex: Int) -> (State, State) {
        // Start by connecting with epsilon.
        var start = State()
        var terminal = start

        loop: for var i = startIndex; i < endIndex; i++ {
          switch characters[i] {
          case "0", "1", "(":
            let ch = characters[i]
            var anotherStart: State, anotherTerminal: State
            // Next index to look ahead for Kleene star.
            var nextIndex: Int
            if ch == "(" {
              nextIndex = matchingBrackets[i]!
              (anotherStart, anotherTerminal) = parseHelper(i + 1, nextIndex)
              nextIndex++
            } else {
              (anotherStart, anotherTerminal) = (State(), State())
              // Concatenation.
              anotherStart.addEdge(Edge(.Normal(ch), dest: anotherTerminal))
              nextIndex = i + 1
            }

            // Look ahead for Kleene stars.
            if nextIndex < endIndex && characters[nextIndex] == "*" {
              // Apply Kleene closure of the new states.
              (anotherStart, anotherTerminal) = closure((anotherStart, anotherTerminal))
              // Skip until after the star.
              i = nextIndex
            } else {
              // Back to the previous char.
              i = nextIndex - 1
            }
            // Update new start and terminal states.
            (start, terminal) = concat((start, terminal), with: (anotherStart, anotherTerminal))
          case "|":
            let (anotherStart, anotherTerminal) = parseHelper(i + 1, endIndex)
            (start, terminal) = union((start, terminal), with: (anotherStart, anotherTerminal))
            break loop
          default:
            fatalError("Cannot recognize the expression.")
          }
        }
        return (start, terminal)
      }
      return parseHelper
    }()

    self.nfa = parse(0, characters.count)
    if compileToDFA {
      self.compileToDFA()
    }
  }

  private func compileToDFA() {
    let alphabet: [Character] = ["0", "1"]
    // Mapping from NFA states to their corresponding DFA state.
    var nfa2dfa = Dictionary<Set<State>, State>()
    let findOrInsert = { (nfaStates: Set<State>) -> State in
      if let s = nfa2dfa[nfaStates] {
        return s
      } else {
        let dfaState = State()
        nfa2dfa[nfaStates] = dfaState
        return dfaState
      }
    }

    // Traverse by DFS to add edges within DFA states.
    let initNFAStates = self.nfa.start.getClosure()
    self.dfa = (start: findOrInsert(initNFAStates), terminals: Set<State>())
    var nfaStatesStack: [Set<State>] = [initNFAStates]
    var nfaStatesVisited: Set<Set<State>> = []
    while !nfaStatesStack.isEmpty {
      let poppedNFAStates = nfaStatesStack.removeLast()
      if nfaStatesVisited.contains(poppedNFAStates) { continue }

      nfaStatesVisited.insert(poppedNFAStates)
      let poppedDFAState = findOrInsert(poppedNFAStates)
      // Mark terminal if containing terminal NFA state.
      if poppedNFAStates.contains(self.nfa.terminal) {
        self.dfa!.terminals.insert(poppedDFAState)
      }

      for ch in alphabet {
        // Step.
        var nextNFAStates = poppedNFAStates.reduce(Set<State>(), combine: { (acc, state) in
          acc.union(state.step(ch))
        })
        // Then closure.
        nextNFAStates = nextNFAStates.reduce(Set<State>(), combine: { $0.union($1.getClosure()) })
        // Skip empty states.
        if nextNFAStates.isEmpty { continue }

        let nextDFAState = findOrInsert(nextNFAStates)
        poppedDFAState.addEdge(Edge(.Normal(ch), dest: nextDFAState))
        nfaStatesStack.append(nextNFAStates)
      }
    }
  }

  private func matchNFA(s: String) -> Bool {
    let (start, terminal) = nfa
    var states = start.getClosure()
    for ch in s.characters {
      states = states.reduce(Set<State>(), combine: { (acc, state) in
        acc.union(state.step(ch))
      })
      if states.isEmpty {
        return false
      }
    }
    // Get the final set of states included in their closures.
    states = states.reduce(Set<State>(), combine: { $0.union($1.getClosure()) })
    return states.contains(terminal)
  }

  private func matchDFA(s: String) -> Bool {
    let (start, terminals) = dfa!
    var state = start
    for ch in s.characters {
      if let newState: State = state.step(ch) {
        state = newState
      } else {
        return false
      }
    }
    return terminals.contains(state)
  }

  public func test(s: String) -> Bool {
    if dfa == nil {
      return matchNFA(s)
    } else {
      return matchDFA(s)
    }
  }
  
}
