//===-- IsFeatureEnabledTests.cpp -------------------------------*- C++ -*-===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#include "FeatureParsingTest.h"
#include <map>

using namespace swift;

namespace {

static const FeatureWrapper baselineF(Feature::AsyncAwait);
static const FeatureWrapper upcomingF(Feature::DynamicActorIsolation);
static const FeatureWrapper experimentalF(Feature::NamedOpaqueTypes);
static const FeatureWrapper strictConcurrencyF(Feature::StrictConcurrency);

using FeatureState = LangOptions::FeatureState;

using IsFeatureEnabledTestCase =
    ArgParsingTestCase<std::map<Feature, FeatureState::Kind>>;

class IsFeatureEnabledTest
    : public FeatureParsingTest,
      public ::testing::WithParamInterface<IsFeatureEnabledTestCase> {};

// Test that the chosen features for testing match our expectations.
TEST_F(IsFeatureEnabledTest, VerifyTestedFeatures) {
  auto feature = baselineF;
  {
    ASSERT_FALSE(getUpcomingFeature(feature.name));
    ASSERT_FALSE(getExperimentalFeature(feature.name));
    ASSERT_FALSE(isFeatureAdoptable(feature));
  }

  feature = upcomingF;
  {
    ASSERT_TRUE(getUpcomingFeature(feature.name));
    ASSERT_FALSE(isFeatureAdoptable(feature));
    ASSERT_LT(defaultLangMode, feature.langMode);
  }

  feature = strictConcurrencyF;
  {
    ASSERT_TRUE(getUpcomingFeature(feature.name));
    ASSERT_FALSE(isFeatureAdoptable(feature));
    ASSERT_LT(defaultLangMode, feature.langMode);
  }

  feature = experimentalF;
  {
    ASSERT_TRUE(getExperimentalFeature(feature.name));
    ASSERT_FALSE(isFeatureAdoptable(feature));
  }
}

TEST_P(IsFeatureEnabledTest, ) {
  auto &testCase = GetParam();
  parseArgs(testCase.args);

  for (auto &pair : testCase.expectedResult) {
    auto feature = pair.first;
    auto actualState = getLangOptions().getFeatureState(feature);
    auto expectedState = pair.second;
    ASSERT_EQ(actualState, expectedState)
        << "Feature: " + getFeatureName(feature).str();
  }
}

// MARK: - Default state

// clang-format off
static const IsFeatureEnabledTestCase defaultStateTestCases[] = {
  IsFeatureEnabledTestCase(
      {}, {
        {baselineF, FeatureState::Enabled},
        {upcomingF, FeatureState::Off},
        {strictConcurrencyF, FeatureState::Off},
        {experimentalF, FeatureState::Off},
      }),
  IsFeatureEnabledTestCase(
      {"-swift-version", upcomingF.langMode},
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase(
      {"-swift-version", strictConcurrencyF.langMode},
      {{strictConcurrencyF, FeatureState::Enabled}}),
};
// clang-format on
INSTANTIATE_TEST_SUITE_P(DefaultState, IsFeatureEnabledTest,
                         ::testing::ValuesIn(defaultStateTestCases));

// MARK: - Single enable

// clang-format off
static const IsFeatureEnabledTestCase singleEnableTestCases[] = {
  IsFeatureEnabledTestCase(
      {"-enable-upcoming-feature", baselineF.name},
      {{baselineF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase(
      {"-enable-upcoming-feature", baselineF.name + ":undef"},
      {{baselineF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase(
      {"-enable-upcoming-feature", baselineF.name + ":adoption"},
      {{baselineF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase(
      {"-enable-experimental-feature", baselineF.name},
      {{baselineF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase(
      {"-enable-experimental-feature", baselineF.name + ":undef"},
      {{baselineF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase(
      {"-enable-experimental-feature", baselineF.name + ":adoption"},
      {{baselineF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase(
      {"-enable-upcoming-feature", upcomingF.name},
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase(
      {"-enable-upcoming-feature", upcomingF.name + ":undef"},
      {{upcomingF, FeatureState::Off}}),
  IsFeatureEnabledTestCase(
      {"-enable-upcoming-feature", upcomingF.name + ":adoption"},
      {{upcomingF, FeatureState::Off}}),
  IsFeatureEnabledTestCase(
      {"-enable-experimental-feature", upcomingF.name},
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase(
      {"-enable-experimental-feature", upcomingF.name + ":undef"},
      {{upcomingF, FeatureState::Off}}),
  IsFeatureEnabledTestCase(
      {"-enable-experimental-feature", upcomingF.name + ":adoption"},
      {{upcomingF, FeatureState::Off}}),
  IsFeatureEnabledTestCase(
      {"-enable-upcoming-feature", strictConcurrencyF.name},
      {{strictConcurrencyF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase(
      {"-enable-upcoming-feature", strictConcurrencyF.name + ":undef"},
      {{strictConcurrencyF, FeatureState::Off}}),
  IsFeatureEnabledTestCase(
      {"-enable-upcoming-feature", strictConcurrencyF.name + ":adoption"},
      {{strictConcurrencyF, FeatureState::Off}}),
  IsFeatureEnabledTestCase(
      {"-enable-experimental-feature", strictConcurrencyF.name},
      {{strictConcurrencyF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase(
      {"-enable-experimental-feature", strictConcurrencyF.name + ":undef"},
      {{strictConcurrencyF, FeatureState::Off}}),
  IsFeatureEnabledTestCase(
      {"-enable-experimental-feature", strictConcurrencyF.name + ":adoption"},
      {{strictConcurrencyF, FeatureState::Off}}),
  IsFeatureEnabledTestCase(
      {"-enable-upcoming-feature", experimentalF.name},
      {{experimentalF, FeatureState::Off}}),
  IsFeatureEnabledTestCase(
      {"-enable-upcoming-feature", experimentalF.name + ":undef"},
      {{experimentalF, FeatureState::Off}}),
  IsFeatureEnabledTestCase(
      {"-enable-upcoming-feature", experimentalF.name + ":adoption"},
      {{experimentalF, FeatureState::Off}}),
  IsFeatureEnabledTestCase(
      {"-enable-experimental-feature", experimentalF.name},
      {{experimentalF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase(
      {"-enable-experimental-feature", experimentalF.name + ":undef"},
      {{experimentalF, FeatureState::Off}}),
  IsFeatureEnabledTestCase(
      {"-enable-experimental-feature", experimentalF.name + ":adoption"},
      {{experimentalF, FeatureState::Off}}),
};
// clang-format on
INSTANTIATE_TEST_SUITE_P(SingleEnable, IsFeatureEnabledTest,
                         ::testing::ValuesIn(singleEnableTestCases));

// MARK: - Single disable

// clang-format off
static const IsFeatureEnabledTestCase singleDisableTestCases[] = {
  IsFeatureEnabledTestCase(
      {"-disable-upcoming-feature", baselineF.name},
      {{baselineF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase(
      {"-disable-experimental-feature", baselineF.name},
      {{baselineF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase(
      {"-disable-upcoming-feature", upcomingF.name},
      {{upcomingF, FeatureState::Off}}),
  IsFeatureEnabledTestCase(
      {"-disable-experimental-feature", upcomingF.name},
      {{upcomingF, FeatureState::Off}}),

  // Disabling in target language mode has no effect.
  IsFeatureEnabledTestCase({
        "-swift-version", upcomingF.langMode,
        "-disable-upcoming-feature", upcomingF.name,
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-swift-version", upcomingF.langMode,
        "-disable-experimental-feature", upcomingF.name,
      },
      {{upcomingF, FeatureState::Enabled}}),

  IsFeatureEnabledTestCase(
      {"-disable-upcoming-feature", strictConcurrencyF.name},
      {{strictConcurrencyF, FeatureState::Off}}),
  IsFeatureEnabledTestCase(
      {"-disable-experimental-feature", strictConcurrencyF.name},
      {{strictConcurrencyF, FeatureState::Off}}),

  // Disabling in target language mode has no effect.
  IsFeatureEnabledTestCase({
        "-disable-upcoming-feature", strictConcurrencyF.name,
        "-swift-version", strictConcurrencyF.langMode,
      },
      {{strictConcurrencyF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-disable-experimental-feature", strictConcurrencyF.name,
        "-swift-version", strictConcurrencyF.langMode,
      },
      {{strictConcurrencyF, FeatureState::Enabled}}),

  IsFeatureEnabledTestCase(
      {"-disable-upcoming-feature", experimentalF.name},
      {{experimentalF, FeatureState::Off}}),
  IsFeatureEnabledTestCase(
      {"-disable-experimental-feature", experimentalF.name},
      {{experimentalF, FeatureState::Off}}),
};
// clang-format on
INSTANTIATE_TEST_SUITE_P(SingleDisable, IsFeatureEnabledTest,
                         ::testing::ValuesIn(singleDisableTestCases));

// MARK: - Double enable

// clang-format off
static const IsFeatureEnabledTestCase doubleEnableTestCases[] = {
  IsFeatureEnabledTestCase({
        "-enable-upcoming-feature", upcomingF.name + ":undef",
        "-enable-upcoming-feature", upcomingF.name,
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-upcoming-feature", upcomingF.name + ":adoption",
        "-enable-upcoming-feature", upcomingF.name,
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-upcoming-feature", upcomingF.name,
        "-enable-upcoming-feature", upcomingF.name + ":undef",
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-upcoming-feature", upcomingF.name,
        "-enable-upcoming-feature", upcomingF.name + ":adoption",
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-upcoming-feature", upcomingF.name + ":undef",
        "-enable-experimental-feature", upcomingF.name,
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-upcoming-feature", upcomingF.name + ":adoption",
        "-enable-experimental-feature", upcomingF.name,
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-upcoming-feature", upcomingF.name,
        "-enable-experimental-feature", upcomingF.name + ":undef",
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-upcoming-feature", upcomingF.name,
        "-enable-experimental-feature", upcomingF.name + ":adoption",
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", upcomingF.name + ":undef",
        "-enable-upcoming-feature", upcomingF.name,
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", upcomingF.name + ":adoption",
        "-enable-upcoming-feature", upcomingF.name,
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", upcomingF.name,
        "-enable-upcoming-feature", upcomingF.name + ":undef",
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", upcomingF.name,
        "-enable-upcoming-feature", upcomingF.name + ":adoption",
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", upcomingF.name + ":undef",
        "-enable-experimental-feature", upcomingF.name,
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", upcomingF.name + ":adoption",
        "-enable-experimental-feature", upcomingF.name,
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", upcomingF.name,
        "-enable-experimental-feature", upcomingF.name + ":undef",
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", upcomingF.name,
        "-enable-experimental-feature", upcomingF.name + ":adoption",
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", experimentalF.name + ":undef",
        "-enable-experimental-feature", experimentalF.name,
      },
      {{experimentalF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", experimentalF.name + ":adoption",
        "-enable-experimental-feature", experimentalF.name,
      },
      {{experimentalF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", experimentalF.name,
        "-enable-experimental-feature", experimentalF.name + ":undef",
      },
      {{experimentalF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", experimentalF.name,
        "-enable-experimental-feature", experimentalF.name + ":adoption",
      },
      {{experimentalF, FeatureState::Enabled}}),
};
// clang-format on
INSTANTIATE_TEST_SUITE_P(DoubleEnable, IsFeatureEnabledTest,
                         ::testing::ValuesIn(doubleEnableTestCases));

// MARK: - Enable / disable

// clang-format off
static const IsFeatureEnabledTestCase enableDisableTestCases[] = {
  IsFeatureEnabledTestCase({
        "-enable-upcoming-feature", upcomingF.name,
        "-disable-upcoming-feature", upcomingF.name,
      },
      {{upcomingF, FeatureState::Off}}),
  IsFeatureEnabledTestCase({
        "-enable-upcoming-feature", upcomingF.name,
        "-disable-upcoming-feature", upcomingF.name + ":undef",
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-upcoming-feature", upcomingF.name,
        "-disable-upcoming-feature", upcomingF.name + ":adoption",
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-disable-upcoming-feature", upcomingF.name,
        "-enable-upcoming-feature", upcomingF.name,
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", upcomingF.name,
        "-disable-upcoming-feature", upcomingF.name,
      },
      {{upcomingF, FeatureState::Off}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", upcomingF.name,
        "-disable-upcoming-feature", upcomingF.name + ":undef",
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", upcomingF.name,
        "-disable-upcoming-feature", upcomingF.name + ":adoption",
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-disable-experimental-feature", upcomingF.name,
        "-enable-upcoming-feature", upcomingF.name,
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-upcoming-feature", upcomingF.name,
        "-disable-experimental-feature", upcomingF.name,
      },
      {{upcomingF, FeatureState::Off}}),
  IsFeatureEnabledTestCase({
        "-enable-upcoming-feature", upcomingF.name,
        "-disable-experimental-feature", upcomingF.name + ":undef",
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-upcoming-feature", upcomingF.name,
        "-disable-experimental-feature", upcomingF.name + ":adoption",
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-disable-upcoming-feature", upcomingF.name,
        "-enable-experimental-feature", upcomingF.name,
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", upcomingF.name,
        "-disable-experimental-feature", upcomingF.name,
      },
      {{upcomingF, FeatureState::Off}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", upcomingF.name,
        "-disable-experimental-feature", upcomingF.name + ":undef",
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", upcomingF.name,
        "-disable-experimental-feature", upcomingF.name + ":adoption",
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-disable-experimental-feature", upcomingF.name,
        "-enable-experimental-feature", upcomingF.name,
      },
      {{upcomingF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", experimentalF.name,
        "-disable-experimental-feature", experimentalF.name,
      },
      {{experimentalF, FeatureState::Off}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", experimentalF.name,
        "-disable-experimental-feature", experimentalF.name + ":undef",
      },
      {{experimentalF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-enable-experimental-feature", experimentalF.name,
        "-disable-experimental-feature", experimentalF.name + ":adoption",
      },
      {{experimentalF, FeatureState::Enabled}}),
  IsFeatureEnabledTestCase({
        "-disable-experimental-feature", experimentalF.name,
        "-enable-experimental-feature", experimentalF.name,
      },
      {{experimentalF, FeatureState::Enabled}}),
};
// clang-format on
INSTANTIATE_TEST_SUITE_P(EnableDisable, IsFeatureEnabledTest,
                         ::testing::ValuesIn(enableDisableTestCases));

// MARK: - Last option wins

// clang-format off
static const IsFeatureEnabledTestCase lastOptionWinsTestCases[] = {
  IsFeatureEnabledTestCase({
        "-enable-upcoming-feature", upcomingF.name,
        "-disable-upcoming-feature", upcomingF.name,
        "-enable-experimental-feature", experimentalF.name,
        "-disable-upcoming-feature", upcomingF.name,
        "-enable-upcoming-feature", upcomingF.name,
        "-disable-experimental-feature", experimentalF.name,
        "-disable-upcoming-feature", upcomingF.name,
      }, {
        {upcomingF, FeatureState::Off},
        {experimentalF, FeatureState::Off}
      }),
  IsFeatureEnabledTestCase({
        "-enable-upcoming-feature", upcomingF.name,
        "-disable-upcoming-feature", upcomingF.name,
        "-enable-experimental-feature", experimentalF.name,
        "-disable-upcoming-feature", upcomingF.name,
        "-enable-upcoming-feature", upcomingF.name,
        "-disable-experimental-feature", experimentalF.name,
        "-disable-upcoming-feature", upcomingF.name,
        "-enable-experimental-feature", experimentalF.name,
        "-enable-upcoming-feature", upcomingF.name,
      }, {
        {upcomingF, FeatureState::Enabled},
        {experimentalF, FeatureState::Enabled}
      }),
  IsFeatureEnabledTestCase({
        "-enable-upcoming-feature", strictConcurrencyF.name + "=targeted",
        "-disable-upcoming-feature", strictConcurrencyF.name,
        "-enable-upcoming-feature", strictConcurrencyF.name + "=minimal",
      },
      {{strictConcurrencyF, FeatureState::Off}}), // FIXME?
  IsFeatureEnabledTestCase({
        "-enable-upcoming-feature", strictConcurrencyF.name + "=targeted",
        "-enable-upcoming-feature", strictConcurrencyF.name + "=complete",
        "-disable-upcoming-feature", strictConcurrencyF.name,
      },
      {{strictConcurrencyF, FeatureState::Enabled}}), // FIXME?
};
// clang-format on
INSTANTIATE_TEST_SUITE_P(LastOptionWins, IsFeatureEnabledTest,
                         ::testing::ValuesIn(lastOptionWinsTestCases));

} // end anonymous namespace
