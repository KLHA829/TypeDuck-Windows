#include "gtest/gtest.h"
#include "gmock/gmock.h"

#include <cstdint>
#include <cstring>
#include <string>

#include "proto/ProtoFraming.h"
#include "proto/moqi.pb.h"

namespace {

std::string frameWithDeclaredSize(std::uint32_t declaredSize,
                                  const std::string &body = std::string()) {
  std::string frame(sizeof(std::uint32_t), '\0');
  std::memcpy(&frame[0], &declaredSize, sizeof(declaredSize));
  frame.append(body);
  return frame;
}

} // namespace

TEST(TypeDuckProtoFraming, SerializeMessageBoundedMustNotBeFramedAgain) {
  // Regression for MoqLauncher BackendServer::handleBackendReply: latency
  // annotate briefly called framePayload() on serializeMessageBounded output
  // (double length-prefix). TSF then failed to parse ServerResponse.
  moqi::protocol::ServerResponse response;
  response.set_success(true);
  response.set_seq_num(1);
  response.set_client_id("regression-client");

  Moqi::Proto::FramedMessage once;
  ASSERT_TRUE(Moqi::Proto::serializeMessageBounded(
      response, once, Moqi::Proto::kMaxClientFramePayloadBytes));

  Moqi::Proto::FrameBuffer onceBuf{Moqi::Proto::kMaxClientFramePayloadBytes};
  onceBuf.append(once.data(), once.size());
  std::string oncePayload;
  ASSERT_TRUE(onceBuf.nextFrame(oncePayload));
  moqi::protocol::ServerResponse parsedOnce;
  ASSERT_TRUE(Moqi::Proto::parsePayload(oncePayload, parsedOnce));
  EXPECT_TRUE(parsedOnce.success());
  EXPECT_EQ(parsedOnce.client_id(), "regression-client");

  // Old mistake pattern: frame an already-framed buffer (string overload only).
  const std::string onceWire(once.data(), once.size());
  const auto twice = Moqi::Proto::framePayload(onceWire);
  Moqi::Proto::FrameBuffer twiceBuf{Moqi::Proto::kMaxClientFramePayloadBytes};
  twiceBuf.append(twice.data(), twice.size());
  std::string twicePayload;
  ASSERT_TRUE(twiceBuf.nextFrame(twicePayload));
  moqi::protocol::ServerResponse parsedTwice;
  EXPECT_FALSE(Moqi::Proto::parsePayload(twicePayload, parsedTwice))
      << "double-framed outbound must not parse as ServerResponse";
}

TEST(TypeDuckProtoFraming, UsesOneMiBClientAndBackendFrameCaps) {
  EXPECT_EQ(Moqi::Proto::kMaxClientFramePayloadBytes, 1024u * 1024u);
  EXPECT_EQ(Moqi::Proto::kMaxBackendFramePayloadBytes, 1024u * 1024u);
}

TEST(TypeDuckProtoFraming, RejectsOversizedFrameAndDropsBody) {
  Moqi::Proto::FrameBuffer buffer(8);
  const std::string frame = frameWithDeclaredSize(9, "abcdefghi");

  buffer.append(frame.data(), frame.size());

  std::string payload;
  EXPECT_FALSE(buffer.nextFrame(payload));
  EXPECT_EQ(buffer.lastError(), Moqi::Proto::FrameError::PayloadTooLarge);
  EXPECT_TRUE(buffer.hasViolation());
  EXPECT_EQ(buffer.bufferedBytes(), 0u);
  EXPECT_TRUE(payload.empty());
}

TEST(TypeDuckProtoFraming, TruncatedFrameRemainsPendingOnlyWithinLimit) {
  Moqi::Proto::FrameBuffer buffer(8);
  const std::string partial = frameWithDeclaredSize(8, "abc");

  buffer.append(partial.data(), partial.size());

  std::string payload;
  EXPECT_FALSE(buffer.nextFrame(payload));
  EXPECT_EQ(buffer.lastError(), Moqi::Proto::FrameError::Incomplete);
  EXPECT_FALSE(buffer.hasViolation());
  EXPECT_EQ(buffer.bufferedBytes(), partial.size());

  const std::string oversizedHeader = frameWithDeclaredSize(9);
  buffer.clear();
  buffer.append(oversizedHeader.data(), oversizedHeader.size());

  EXPECT_FALSE(buffer.nextFrame(payload));
  EXPECT_EQ(buffer.lastError(), Moqi::Proto::FrameError::PayloadTooLarge);
  EXPECT_TRUE(buffer.hasViolation());
  EXPECT_EQ(buffer.bufferedBytes(), 0u);
}

TEST(TypeDuckProtoFraming, MalformedPayloadDoesNotParseRequestOrResponse) {
  const std::string malformed("\x08\xff\xff\xff", 4);

  moqi::protocol::ClientRequest request;
  moqi::protocol::ServerResponse response;

  EXPECT_FALSE(Moqi::Proto::parsePayload(malformed, request));
  EXPECT_EQ(request.ByteSizeLong(), 0u);
  EXPECT_FALSE(Moqi::Proto::parsePayload(malformed, response));
  EXPECT_EQ(response.ByteSizeLong(), 0u);
}

TEST(TypeDuckProtocol, RawLookupSeparatorsSurviveCandidateComments) {
  moqi::protocol::CandidateEntry candidate;
  const std::string rawComment =
      "\vReverse lookup marker\f\rmatch_input_buffer,honzi,jyutping\rnei,\xE4\xBD\xA0,nei5";

  candidate.set_id("nei-1");
  candidate.set_text("\xE4\xBD\xA0");
  candidate.set_input_code("nei");
  candidate.set_jyutping("nei5");
  candidate.set_raw_lookup_comment(rawComment);
  candidate.set_comment(rawComment);

  std::string serialized;
  ASSERT_TRUE(candidate.SerializeToString(&serialized));

  moqi::protocol::CandidateEntry parsed;
  ASSERT_TRUE(parsed.ParseFromString(serialized));
  EXPECT_EQ(parsed.raw_lookup_comment(), rawComment);
  EXPECT_EQ(parsed.comment(), rawComment);
}
