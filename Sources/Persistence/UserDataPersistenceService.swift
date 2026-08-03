import Foundation

@MainActor
final class UserDataPersistenceService {
    private(set) var userData: AppUserData
    private let saveHandler: (AppUserData) -> Bool

    convenience init(store: UserDataStore = UserDataStore()) {
        self.init(
            initialUserData: store.load(),
            saveHandler: { store.save($0) }
        )
    }

    init(
        initialUserData: AppUserData,
        saveHandler: @escaping (AppUserData) -> Bool
    ) {
        userData = initialUserData
        self.saveHandler = saveHandler
    }

    func replaceUserData(_ updatedUserData: AppUserData) {
        userData = updatedUserData
    }

    func replaceQueue(with snapshot: QueueStoreSnapshot) {
        userData.queue = snapshot.jobs
        userData.queueGroups = snapshot.queueGroups
    }

    @discardableResult
    func save() -> Bool {
        saveHandler(userData)
    }

    @discardableResult
    func save(_ updatedUserData: AppUserData) -> Bool {
        replaceUserData(updatedUserData)
        return save()
    }
}
