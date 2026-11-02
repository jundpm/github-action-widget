import Foundation

enum Diagnostics {
    static func check(_ repo: String) async {
        let client = GitHubClient()
        do {
            let runs = try await client.get("/repos/\(repo)/actions/runs?per_page=5", as: RunsResponse.self).workflowRuns
            print("runs: \(runs.count)")
            for run in runs {
                let jobs = try await client.get(
                    "/repos/\(repo)/actions/runs/\(run.id)/jobs?per_page=50", as: JobsResponse.self).jobs
                let p = RunProgress(jobs: jobs)
                print("#\(run.runNumber) \(run.workflowName) [\(run.visual.label)] \(run.headBranch ?? "-")"
                      + " jobs=\(jobs.count) steps=\(p?.doneSteps ?? 0)/\(p?.totalSteps ?? 0) caption=\(p?.caption ?? "-")")
            }
            print("rate remaining: \(await client.rateRemaining ?? -1)")
        } catch {
            print("error: \(error.localizedDescription)")
        }
    }
}
