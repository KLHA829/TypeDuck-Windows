#ifndef _Moqi_LAUNCHER_PROCESS_IDENTITY_H_
#define _Moqi_LAUNCHER_PROCESS_IDENTITY_H_

#include <string>

namespace Moqi {

// Returns true when this process may host the per-user named pipe (interactive
// user, medium integrity, not elevated / LocalSystem).
bool isLauncherProcessIdentityAllowed();

// Non-zero WinMain exit when another instance holds the mutex but the
// interactive user's pipe is missing (e.g. only SYSTEM pipe exists).
int exitCodeForExistingLauncherMutexConflict();

void showLauncherWrongProcessIdentityMessage();
void showLauncherMutexConflictMessage(bool systemPipePresent);

bool isNamedPipePresent(const std::wstring& pipePath);

constexpr int kExitLauncherWrongProcessIdentity = 10;
constexpr int kExitLauncherMutexHeldWrongPipe = 11;

} // namespace Moqi

#endif // _Moqi_LAUNCHER_PROCESS_IDENTITY_H_
