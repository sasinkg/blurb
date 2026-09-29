const MONTH_KEY_PATTERN = /^\d{4}-(0[1-9]|1[0-2])$/;

function photoMonthKey(date, timeZone = "America/Los_Angeles") {
  const parts = new Intl.DateTimeFormat("en-US", {
    year: "numeric",
    month: "2-digit",
    timeZone,
  }).formatToParts(date);
  const year = parts.find((part) => part.type === "year")?.value;
  const month = parts.find((part) => part.type === "month")?.value;
  return `${year}-${month}`;
}

function validateSelectionInput(data) {
  const groupID = typeof data?.groupID === "string" ? data.groupID.trim() : "";
  const postID = typeof data?.postID === "string" ? data.postID.trim() : "";
  const storagePath = typeof data?.storagePath === "string" ? data.storagePath.trim() : "";
  const caption = validateCaption(data?.caption);
  if (!groupID) throw new Error("A group is required.");
  if (Boolean(postID) === Boolean(storagePath)) {
    throw new Error("Choose a photo post or upload a private photo.");
  }
  return {groupID, postID, storagePath, caption};
}

function validateCaption(value) {
  const caption = typeof value === "string" ? value.trim() : "";
  if (caption.length > 180) throw new Error("Keep the photo caption under 180 characters.");
  return caption;
}

function validPrivatePhotoPath(path, groupID, userID, monthKey) {
  const prefix = `photo-of-month/${groupID}/${userID}/${monthKey}/`;
  return path.startsWith(prefix) && /^[0-9a-fA-F-]{36}\.jpg$/.test(path.slice(prefix.length));
}

function selectionDocumentID(groupID, monthKey) {
  if (!groupID || !MONTH_KEY_PATTERN.test(monthKey)) {
    throw new Error("Invalid Photo of the Month document identifier.");
  }
  return `${groupID}_${monthKey}`;
}

function buildSelection({groupID, postID, post, userID, monthKey, caption = ""}) {
  return {
    groupID,
    monthKey,
    userID,
    postID,
    imageURL: post.imageURL,
    authorName: post.authorName ?? "Blurb friend",
    caption: validateCaption(caption),
    postCreatedAt: post.createdAt,
  };
}

module.exports = {
  buildSelection,
  photoMonthKey,
  selectionDocumentID,
  validateCaption,
  validateSelectionInput,
  validPrivatePhotoPath,
};
