const {test} = require("node:test");
const assert = require("node:assert/strict");
const {aggregateCities, normalizeCityLocation} = require("./cityLocations");

test("normalization rejects missing cities and removes surrounding whitespace", () => {
  assert.equal(normalizeCityLocation({region: "CA"}), null);
  assert.deepEqual(normalizeCityLocation({city: " Oakland ", region: " CA ", countryCode: "us"}), {
    city: "Oakland", region: "CA", countryCode: "US", key: "oakland|ca|us",
  });
});

test("aggregation groups normalized cities and sorts by count", () => {
  assert.deepEqual(aggregateCities([
    {city: "Oakland", region: "CA", countryCode: "US"},
    {city: " oakland ", region: "CA", countryCode: "us"},
    {city: "Seattle", region: "WA", countryCode: "US"},
    null,
  ]), [
    {city: "Oakland", region: "CA", countryCode: "US", count: 2},
    {city: "Seattle", region: "WA", countryCode: "US", count: 1},
  ]);
});
