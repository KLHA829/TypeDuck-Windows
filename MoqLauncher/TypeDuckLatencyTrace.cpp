#include "TypeDuckLatencyTrace.h"

#include <algorithm>
#include <cctype>
#include <fstream>
#include <sstream>

namespace TypeDuck::LatencyTrace {
namespace {

thread_local Session *g_currentSession = nullptr;

bool envFlagEnabled(const wchar_t *name) {
  const wchar_t *value = _wgetenv(name);
  if (value == nullptr || *value == L'\0') {
    return false;
  }
  std::wstring normalized(value);
  std::transform(normalized.begin(), normalized.end(), normalized.begin(),
                 [](wchar_t ch) {
                   return static_cast<wchar_t>(std::towlower(ch));
                 });
  return normalized == L"1" || normalized == L"true" || normalized == L"yes" ||
         normalized == L"on";
}

std::wstring latencyLogPath() {
  const wchar_t *localAppData = _wgetenv(L"LOCALAPPDATA");
  if (localAppData == nullptr || *localAppData == L'\0') {
    return L"";
  }
  return std::wstring(localAppData) + L"\\TypeDuckIME\\Log\\latency-trace.ndjson";
}

std::string methodToken(moqi::protocol::Method method) {
  switch (method) {
  case moqi::protocol::METHOD_FILTER_KEY_DOWN:
    return "filterKeyDown";
  case moqi::protocol::METHOD_ON_KEY_DOWN:
    return "onKeyDown";
  case moqi::protocol::METHOD_FILTER_KEY_UP:
    return "filterKeyUp";
  case moqi::protocol::METHOD_ON_KEY_UP:
    return "onKeyUp";
  default:
    return "method_" + std::to_string(static_cast<int>(method));
  }
}

double microsToMillis(std::uint64_t micros) {
  return static_cast<double>(micros) / 1000.0;
}

std::string escapeJsonString(const std::string &value) {
  std::string escaped;
  escaped.reserve(value.size() + 8);
  for (char ch : value) {
    switch (ch) {
    case '\\':
      escaped += "\\\\";
      break;
    case '"':
      escaped += "\\\"";
      break;
    default:
      escaped += ch;
      break;
    }
  }
  return escaped;
}

void appendLatencyLogLine(const std::string &line) {
  const std::wstring path = latencyLogPath();
  if (path.empty()) {
    return;
  }

  std::wofstream stream(path, std::ios::app);
  if (!stream.is_open()) {
    return;
  }

  const int wideLen = ::MultiByteToWideChar(CP_UTF8, 0, line.data(),
                                            static_cast<int>(line.size()),
                                            nullptr, 0);
  if (wideLen <= 0) {
    return;
  }
  std::wstring wideLine(wideLen, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, line.data(), static_cast<int>(line.size()),
                        wideLine.data(), wideLen);
  stream << wideLine << L"\n";
}

} // namespace

bool isEnabled() { return envFlagEnabled(L"TYPEDUCK_LATENCY_TRACE"); }

bool isKeyPathMethod(moqi::protocol::Method method) {
  return method == moqi::protocol::METHOD_FILTER_KEY_DOWN ||
         method == moqi::protocol::METHOD_ON_KEY_DOWN;
}

Session *currentSession() { return g_currentSession; }

void setCurrentSession(Session *session) { g_currentSession = session; }

Session::Session(moqi::protocol::Method method) : method_(method) {
  ::QueryPerformanceFrequency(&frequency_);
  ::QueryPerformanceCounter(&started_);
  lastMark_ = started_;
  setCurrentSession(this);
}

Session::~Session() {
  if (!finished_ && g_currentSession == this) {
    setCurrentSession(nullptr);
  }
}

std::uint64_t Session::elapsedMicrosSince(const LARGE_INTEGER &from) const {
  LARGE_INTEGER now{};
  ::QueryPerformanceCounter(&now);
  if (frequency_.QuadPart == 0) {
    return 0;
  }
  const double seconds =
      static_cast<double>(now.QuadPart - from.QuadPart) /
      static_cast<double>(frequency_.QuadPart);
  return static_cast<std::uint64_t>(seconds * 1000000.0);
}

void Session::appendLocalHop(const char *hopName, std::uint64_t durationUs) {
  moqi::protocol::TypeDuckLatencyHop hop;
  hop.set_hop(hopName);
  hop.set_duration_us(durationUs);
  localHops_.push_back(std::move(hop));
}

void Session::mark(const char *hopName) {
  const std::uint64_t durationUs = elapsedMicrosSince(lastMark_);
  appendLocalHop(hopName, durationUs);
  ::QueryPerformanceCounter(&lastMark_);
}

void Session::mergeRemoteReport(
    const moqi::protocol::TypeDuckLatencyReport &report) {
  remoteHops_.clear();
  remoteHops_.reserve(report.hops_size());
  for (const auto &hop : report.hops()) {
    remoteHops_.push_back(hop);
  }
}

void Session::finish(std::uint32_t seqNum) {
  if (finished_) {
    return;
  }
  finished_ = true;

  const std::uint64_t totalUs = elapsedMicrosSince(started_);

  std::ostringstream json;
  json.setf(std::ios::fixed);
  json.precision(3);
  json << "{\"event\":\"typeduck_latency\""
       << ",\"seq\":" << seqNum << ",\"method\":\""
       << escapeJsonString(methodToken(method_)) << "\""
       << ",\"total_ms\":" << microsToMillis(totalUs) << ",\"hops\":[";

  bool firstHop = true;
  auto appendHop = [&](const moqi::protocol::TypeDuckLatencyHop &hop) {
    if (!firstHop) {
      json << ',';
    }
    firstHop = false;
    json << "{\"hop\":\"" << escapeJsonString(hop.hop()) << "\",\"ms\":"
         << microsToMillis(hop.duration_us()) << '}';
  };

  for (const auto &hop : localHops_) {
    appendHop(hop);
  }
  for (const auto &hop : remoteHops_) {
    appendHop(hop);
  }
  json << "]}";

  appendLatencyLogLine(json.str());

  if (g_currentSession == this) {
    setCurrentSession(nullptr);
  }
}

void noteCandidateUiUpdate() {
  Session *session = currentSession();
  if (session == nullptr) {
    return;
  }
  session->mark("tsf_candidate_ui");
}

} // namespace TypeDuck::LatencyTrace
