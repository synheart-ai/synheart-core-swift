import Foundation

enum DeletionOutcome {
    static func accountResult(
        serverAccepted: Bool,
        localWiped: Bool
    ) -> DeletionRequestResult {
        switch (serverAccepted, localWiped) {
        case (true, true):
            return DeletionRequestResult(
                status: "accepted",
                message: "Server deletion requested and local data wiped.",
                serverDeletionRequested: true,
                localDataWiped: true
            )
        case (true, false):
            return DeletionRequestResult(
                status: "partial",
                message: "Server deletion was requested, but local data could not be wiped.",
                serverDeletionRequested: true,
                localDataWiped: false
            )
        case (false, true):
            return DeletionRequestResult(
                status: "local_only",
                message: "Local data was wiped, but the server deletion request failed.",
                serverDeletionRequested: false,
                localDataWiped: true
            )
        case (false, false):
            return DeletionRequestResult(
                status: "failed",
                message: "Neither server deletion nor local data wipe succeeded.",
                serverDeletionRequested: false,
                localDataWiped: false
            )
        }
    }
}
