const {test} = require("node:test");
const assert = require("node:assert/strict");
const {memberQuestionCounts, newsletterContext, nudgeMessage} = require("./monthlyProgress");

test("newsletter progress unlocks on the first four Fridays at 5 a.m. Pacific", () => {
  assert.equal(newsletterContext(new Date("2026-09-04T11:59:00Z")).releasedCount, 0);
  assert.deepEqual(newsletterContext(new Date("2026-09-04T12:01:00Z")).promptIDs, ["newsletter-2026-9-1"]);
  assert.equal(newsletterContext(new Date("2026-09-26T17:00:00Z")).releasedCount, 4);
});

test("member question progress counts each released question once", () => {
  const counts = memberQuestionCounts([
    {authorID: "maya", promptID: "newsletter-2026-9-1"},
    {authorID: "maya", promptID: "newsletter-2026-9-1"},
    {authorID: "maya", promptID: "newsletter-custom-2026-09-road-trip"},
    {authorID: "raj", promptID: "newsletter-2026-9-2"},
  ], ["maya", "raj"], [
    "newsletter-2026-9-1",
    "newsletter-2026-9-2",
    "newsletter-custom-2026-09-road-trip",
  ]);
  assert.equal(counts.get("maya"), 2);
  assert.equal(counts.get("raj"), 1);
});

test("nudge copy names only the work that is incomplete", () => {
  assert.deepEqual(nudgeMessage({senderName: "Maya", groupName: "Roosters", needsQuestions: true, needsPhoto: false}), {
    title: "Maya sent a nudge",
    body: "Finish this month’s newsletter questions in Roosters.",
  });
  assert.match(nudgeMessage({needsQuestions: true, needsPhoto: true}).body, /questions and choose your Photo/);
});
