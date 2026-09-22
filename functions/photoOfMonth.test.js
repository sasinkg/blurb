const {test} = require("node:test");
const assert = require("node:assert/strict");
const {
  buildSelection,
  photoMonthKey,
  selectionDocumentID,
  validateSelectionInput,
  validPrivatePhotoPath,
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
    storagePath: "",
  });
  assert.throws(() => validateSelectionInput({groupID: "group"}), /photo post or upload/i);
  assert.throws(() => validateSelectionInput({postID: "post"}), /group/i);
  assert.deepEqual(validateSelectionInput({groupID: "group", storagePath: " photo.jpg "}), {
    groupID: "group", postID: "", storagePath: "photo.jpg",
  });
  assert.throws(() => validateSelectionInput({groupID: "group", postID: "post", storagePath: "photo.jpg"}), /photo post or upload/i);
});

test("private upload paths are scoped to one group, user, and month", () => {
  const path = "photo-of-month/group/user/2026-09/12345678-1234-1234-1234-123456789abc.jpg";
  assert.equal(validPrivatePhotoPath(path, "group", "user", "2026-09"), true);
  assert.equal(validPrivatePhotoPath(path, "other", "user", "2026-09"), false);
  assert.equal(validPrivatePhotoPath(path, "group", "other", "2026-09"), false);
  assert.equal(validPrivatePhotoPath(path, "group", "user", "2026-10"), false);
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
