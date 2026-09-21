const {test} = require("node:test");
const assert = require("node:assert/strict");
const {
  buildSelection,
  photoMonthKey,
  selectionDocumentID,
  validateSelectionInput,
} = require("./photoOfMonth");

test("month keys use the product Pacific time zone", () => {
  const instant = new Date("2026-10-01T06:30:00Z");
  assert.equal(photoMonthKey(instant), "2026-09");
  assert.equal(photoMonthKey(instant, "UTC"), "2026-10");
});

test("selection input trims identifiers and rejects missing values", () => {
  assert.deepEqual(validateSelectionInput({groupID: " group ", postID: " post "}), {
    groupID: "group",
    postID: "post",
  });
  assert.throws(() => validateSelectionInput({groupID: "group"}), /photo post/i);
  assert.throws(() => validateSelectionInput({postID: "post"}), /group/i);
});

test("selection document is unique per group and month", () => {
  assert.equal(selectionDocumentID("friends", "2026-09"), "friends_2026-09");
  assert.throws(() => selectionDocumentID("friends", "September"), /invalid/i);
});

test("selection snapshots recap-safe photo metadata", () => {
  const createdAt = {seconds: 123};
  assert.deepEqual(buildSelection({
    groupID: "friends",
    monthKey: "2026-09",
    postID: "post",
    userID: "user",
    post: {imageURL: "https://example.com/photo.jpg", authorName: "Sasin", createdAt},
  }), {
    groupID: "friends",
    monthKey: "2026-09",
    userID: "user",
    postID: "post",
    imageURL: "https://example.com/photo.jpg",
    authorName: "Sasin",
    postCreatedAt: createdAt,
  });
});
