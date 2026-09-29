const {test} = require("node:test");
const assert = require("node:assert/strict");
const {songDisplayText, validateSongSelectionInput} = require("./songOfMonth");

test("song selections trim title and artist", () => {
  assert.deepEqual(validateSongSelectionInput({
    groupID: " group ", title: " Dreams ", artist: " Fleetwood Mac ",
  }), {
    groupID: "group", title: "Dreams", artist: "Fleetwood Mac", remove: false,
  });
});

test("songs require a title and limit field lengths", () => {
  assert.throws(() => validateSongSelectionInput({groupID: "group"}), /title/i);
  assert.throws(() => validateSongSelectionInput({groupID: "group", title: "x".repeat(101)}), /100/);
  assert.deepEqual(validateSongSelectionInput({groupID: "group", remove: true}), {
    groupID: "group", title: "", artist: "", remove: true,
  });
});

test("song display text includes an artist only when supplied", () => {
  assert.equal(songDisplayText("Dreams", "Fleetwood Mac"), "Dreams — Fleetwood Mac");
  assert.equal(songDisplayText("Dreams", ""), "Dreams");
});
