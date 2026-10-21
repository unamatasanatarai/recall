import Foundation

/// An advisory `flock` held for the app's lifetime, so a second copy (say one in build/ and one
/// in /Applications) cannot record into the same chunk directory. Released automatically when
/// the process exits, even after a crash.
final class SingleInstanceLock {
    enum LockError: Error {
        case alreadyHeld
        case unavailable(Int32)
    }

    private let descriptor: Int32

    init(url: URL) throws {
        let fd = open(url.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            throw LockError.unavailable(errno)
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let error = errno
            close(fd)
            throw error == EWOULDBLOCK ? LockError.alreadyHeld : LockError.unavailable(error)
        }
        descriptor = fd
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
