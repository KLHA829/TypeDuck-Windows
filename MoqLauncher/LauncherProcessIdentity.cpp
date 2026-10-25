#include "LauncherProcessIdentity.h"

#include <Sddl.h>
#include <Windows.h>
#include <Lmcons.h>

#include <vector>

namespace Moqi {

namespace {

constexpr wchar_t kLauncherMessageTitle[] =
    L"TypeDuck 啟動程式 / TypeDuck Launcher";

constexpr wchar_t kSystemLauncherPipe[] =
    L"\\\\.\\pipe\\SYSTEM\\TypeDuckIME\\Launcher";

void showLauncherFatalMessage(const wchar_t* body) {
  ::MessageBoxW(nullptr, body, kLauncherMessageTitle, MB_OK | MB_ICONERROR);
}

bool isProcessTokenElevated(HANDLE token) {
  TOKEN_ELEVATION elevation{};
  DWORD size = 0;
  if (!::GetTokenInformation(token, TokenElevation, &elevation,
                             sizeof(elevation), &size)) {
    return false;
  }
  return elevation.TokenIsElevated != FALSE;
}

bool isProcessLocalSystemSid(HANDLE token) {
  DWORD tokenInfoLen = 0;
  ::GetTokenInformation(token, TokenUser, nullptr, 0, &tokenInfoLen);
  std::vector<BYTE> buffer(tokenInfoLen);
  if (!::GetTokenInformation(token, TokenUser, buffer.data(), tokenInfoLen,
                             &tokenInfoLen)) {
    return false;
  }
  const auto* tokenUser = reinterpret_cast<TOKEN_USER*>(buffer.data());
  return ::IsWellKnownSid(tokenUser->User.Sid, WinLocalSystemSid) != FALSE;
}

bool isProcessIntegrityAboveMedium(HANDLE token) {
  DWORD tokenInfoLen = 0;
  ::GetTokenInformation(token, TokenIntegrityLevel, nullptr, 0, &tokenInfoLen);
  std::vector<BYTE> buffer(tokenInfoLen);
  if (!::GetTokenInformation(token, TokenIntegrityLevel, buffer.data(),
                             tokenInfoLen, &tokenInfoLen)) {
    return false;
  }
  const auto* label = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(buffer.data());
  const DWORD rid = *::GetSidSubAuthority(
      label->Label.Sid,
      static_cast<DWORD>(*::GetSidSubAuthorityCount(label->Label.Sid) - 1));
  return rid > SECURITY_MANDATORY_MEDIUM_RID;
}

bool isInteractiveUserNameLocalSystem() {
  wchar_t username[UNLEN + 1]{};
  DWORD unlen = UNLEN + 1;
  if (!::GetUserNameW(username, &unlen)) {
    return false;
  }
  return _wcsicmp(username, L"SYSTEM") == 0;
}

std::wstring interactiveUserLauncherPipePath() {
  wchar_t username[UNLEN + 1]{};
  DWORD unlen = UNLEN + 1;
  if (!::GetUserNameW(username, &unlen)) {
    return {};
  }
  std::wstring pipePath = L"\\\\.\\pipe\\";
  pipePath += username;
  pipePath += L"\\TypeDuckIME\\Launcher";
  return pipePath;
}

} // namespace

bool isNamedPipePresent(const std::wstring& pipePath) {
  if (pipePath.empty()) {
    return false;
  }
  HANDLE pipe = ::CreateFileW(pipePath.c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                              nullptr, OPEN_EXISTING, 0, nullptr);
  if (pipe != INVALID_HANDLE_VALUE) {
    ::CloseHandle(pipe);
    return true;
  }
  const DWORD err = ::GetLastError();
  return err == ERROR_ACCESS_DENIED || err == ERROR_PIPE_BUSY;
}

bool isLauncherProcessIdentityAllowed() {
  if (isInteractiveUserNameLocalSystem()) {
    return false;
  }
  HANDLE token = nullptr;
  if (!::OpenProcessToken(::GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return false;
  }
  const bool elevated = isProcessTokenElevated(token);
  const bool systemSid = isProcessLocalSystemSid(token);
  const bool highIntegrity = isProcessIntegrityAboveMedium(token);
  ::CloseHandle(token);
  return !elevated && !systemSid && !highIntegrity;
}

void showLauncherWrongProcessIdentityMessage() {
  showLauncherFatalMessage(
      L"TypeDuck 啟動程式必須以目前登入用戶執行，唔可以用系統管理員或 SYSTEM 身分。\n"
      L"TypeDuck Launcher must run as the signed-in user, not as Administrator "
      L"or SYSTEM.");
}

void showLauncherMutexConflictMessage(bool systemPipePresent) {
  if (systemPipePresent) {
    showLauncherFatalMessage(
        L"另一個 TypeDuck 啟動程式正以 SYSTEM 或管理員身分運行，導致候選字無法顯示。\n"
        L"請在工作管理員結束 TypeDuckLauncher.exe，再以一般用戶重新啟動。\n\n"
        L"Another TypeDuck Launcher is running as SYSTEM or Administrator, so "
        L"candidates cannot reach your session.\n"
        L"End TypeDuckLauncher.exe in Task Manager (as admin if needed), then "
        L"restart as your normal user.");
    return;
  }
  showLauncherFatalMessage(
      L"已有 TypeDuck 啟動程式在運行，但找不到你目前用戶的連線管道。\n"
      L"請結束錯誤的 TypeDuckLauncher.exe（可能以管理員或 SYSTEM 執行），再以一般用戶重新啟動。\n\n"
      L"TypeDuck Launcher is already running, but the named pipe for your user "
      L"was not found.\n"
      L"End the wrong TypeDuckLauncher.exe instance (often elevated or SYSTEM), "
      L"then restart as your normal user.");
}

int exitCodeForExistingLauncherMutexConflict() {
  const std::wstring expectedPipe = interactiveUserLauncherPipePath();
  const bool expectedPresent =
      !expectedPipe.empty() && isNamedPipePresent(expectedPipe);
  if (expectedPresent) {
    return 0;
  }
  const bool systemPresent = isNamedPipePresent(kSystemLauncherPipe);
  showLauncherMutexConflictMessage(systemPresent);
  return kExitLauncherMutexHeldWrongPipe;
}

} // namespace Moqi
