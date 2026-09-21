const {test} = require("node:test");
const assert = require("node:assert/strict");
const {localDateKey, unansweredMemberIDs} = require("./socialNudges");

test("localDateKey uses the configured Pacific calendar day", () => {
  assert.equal(localDateKey(new Date("2026-09-21T06:30:00Z")), "2026-09-20");
  assert.equal(localDateKey(new Date("2026-09-21T17:00:00Z")), "2026-09-21");
});

test("social nudges exclude the sender, members who answered, and duplicate IDs", () => {
  assert.deepEqual(unansweredMemberIDs({
    memberIDs: ["andy", "maya", "raj", "raj"],
    senderID: "andy",
    answeredAuthorIDs: ["maya"],
  }), ["raj"]);
});
