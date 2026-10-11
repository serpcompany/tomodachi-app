import Foundation

// MARK: - Running the checks (TOMO_SELFTEST=1, and TomoCoreTests)
//
// Every rule check is a function that reports each result to a `check` closure, `(passed, what)`. The self-test prints
// them ("ok    …" / "FAIL  …") and exits 1 on a failure; TomoCoreTests (`swift test`) turns each into an assertion.

public enum TomoCheck {
    /// Runs `checks`, printing each result; false if any failed.
    public static func run(_ checks: ((Bool, String) -> Void) -> Void) -> Bool {
        var ok = true
        checks { passed, what in
            print(line(passed, what))
            if !passed { ok = false }
        }
        return ok
    }

    /// A result as the self-test prints it.
    public static func line(_ passed: Bool, _ what: String) -> String { (passed ? "ok    " : "FAIL  ") + what }
}
