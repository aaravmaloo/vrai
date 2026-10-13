import Foundation
import VraiGit

extension AppModel {
    public var checksFixture: URL? {
        guard let sandbox = launch.sandbox else { return nil }
        let file = sandbox.appending(path: "checks.json")
        return FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) ? file : nil
    }

    public func makeChecks(for store: RepositoryStore, reference: RepositoryReference) -> ChecksStore {
        if launch.isSandboxed {
            guard let fixture = checksFixture else { return ChecksStore(client: nil) }
            let fallback = ChecksRepository(host: "github.com", owner: "vrai-fixtures", name: reference.name, remote: "origin")
            let now = launch.now
            return ChecksStore(client: FixtureChecksClient(file: fixture), fallback: fallback, now: { now ?? Date() })
        }
        let client = GitHubChecksClient(token: GitHubToken.provider(git: store.git, environment: environment.base))
        return ChecksStore(client: client)
    }
}
