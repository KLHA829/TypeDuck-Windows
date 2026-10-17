#pragma once

#include <Windows.h>
#include <cstdint>
#include <string>
#include <vector>

#include "proto/moqi.pb.h"

namespace TypeDuck::LatencyTrace {

bool isEnabled();

bool isKeyPathMethod(moqi::protocol::Method method);

class Session;

Session *currentSession();
void setCurrentSession(Session *session);

class Session {
public:
  explicit Session(moqi::protocol::Method method);
  ~Session();

  Session(const Session &) = delete;
  Session &operator=(const Session &) = delete;

  moqi::protocol::Method method() const { return method_; }

  void mark(const char *hopName);
  void mergeRemoteReport(const moqi::protocol::TypeDuckLatencyReport &report);
  void finish(std::uint32_t seqNum);

private:
  std::uint64_t elapsedMicrosSince(const LARGE_INTEGER &from) const;
  void appendLocalHop(const char *hopName, std::uint64_t durationUs);

  moqi::protocol::Method method_;
  LARGE_INTEGER frequency_{};
  LARGE_INTEGER started_{};
  LARGE_INTEGER lastMark_{};
  std::vector<moqi::protocol::TypeDuckLatencyHop> localHops_;
  std::vector<moqi::protocol::TypeDuckLatencyHop> remoteHops_;
  bool finished_ = false;
};

void noteCandidateUiUpdate();

} // namespace TypeDuck::LatencyTrace
