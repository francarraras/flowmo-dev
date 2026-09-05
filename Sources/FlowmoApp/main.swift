import FlowmoCLI
import FlowmoCheck
import FlowmoWindow
import Foundation

@main
enum FlowmoApp {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if FlowmoCLI.isInvocation(args) {
            FlowmoCLI.main(runChecks: runFlowmoChecks)
        } else {
            FlowmoRuntime.run()
        }
    }
}
