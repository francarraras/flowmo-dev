import Foundation
import FlowmoCheck
import FlowmoCLI
import FlowmoWindow

@main
enum FlowmoApp {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "check" {
            exit(runFlowmoChecks())
        }
        if FlowmoCLI.isInvocation(args) {
            FlowmoCLI.main()
        } else {
            FlowmoRuntime.run()
        }
    }
}
