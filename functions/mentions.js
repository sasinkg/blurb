const normalize = (value) => String(value).normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();

function mentionedNames(text) {
  return new Set([...String(text ?? "").matchAll(/(?<![\p{L}\p{N}_])@([\p{L}\p{M}][\p{L}\p{M}\p{N}_’\-]*)/gu)]
      .map((match) => normalize(match[1])));
}

function mentionRecipients(text, members, senderID, previousText = "") {
  const names = mentionedNames(text);
  for (const oldName of mentionedNames(previousText)) names.delete(oldName);
  const byName = new Map();
  for (const member of members) {
    const first = normalize(String(member.displayName ?? "").trim().split(/\s+/)[0]);
    if (!first) continue;
    const matches = byName.get(first) ?? new Set();
    matches.add(member.id);
    byName.set(first, matches);
  }
  // First-name-only mentions cannot identify one of two namesakes safely.
  return [...new Set([...names].flatMap((name) => {
    const matches = [...(byName.get(name) ?? [])];
    return matches.length === 1 && matches[0] !== senderID ? matches : [];
  }))];
}

function notificationRecipients({text, members, senderID, postAuthorID, previousText}) {
  const recipients = new Map(mentionRecipients(text, members, senderID, previousText)
      .map((id) => [id, "mention"]));
  if (postAuthorID && postAuthorID !== senderID && members.some((member) => member.id === postAuthorID) && !recipients.has(postAuthorID)) {
    recipients.set(postAuthorID, "answerReply");
  }
  return recipients;
}

module.exports = {mentionedNames, mentionRecipients, notificationRecipients};
